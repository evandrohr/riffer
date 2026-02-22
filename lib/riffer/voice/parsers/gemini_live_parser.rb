# frozen_string_literal: true
# rbs_inline: enabled

# Parses Gemini Live realtime payloads into normalized voice events.
class Riffer::Voice::Parsers::GeminiLiveParser < Riffer::Voice::Parsers::Base
  #: (Hash[Symbol | String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def call(payload)
    data = normalize_hash(payload)
    events = [] #: Array[Riffer::Voice::Events::Base]

    server_content = fetch_any(data, ["serverContent", "server_content"]) || {}
    events.concat(extract_audio_chunk(server_content))
    events.concat(extract_input_transcript(server_content))
    events.concat(extract_output_transcript(server_content))
    events.concat(extract_tool_calls(data, server_content))
    events.concat(extract_interrupt(data, server_content))
    events.concat(extract_turn_complete(data, server_content))
    events.concat(extract_usage(data, server_content))
    events
  end

  private

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def extract_audio_chunk(server_content)
    model_turn = fetch_any(server_content, ["modelTurn", "model_turn"]) || {}
    parts = Array(model_turn["parts"])

    parts.filter_map do |part|
      next unless part.is_a?(Hash)
      inline_data = fetch_any(part, ["inlineData", "inline_data"])
      next unless inline_data.is_a?(Hash)

      payload = inline_data["data"]
      next if payload.nil? || payload.to_s.empty?

      mime_type = fetch_any(inline_data, ["mimeType", "mime_type"]) || "audio/pcm"
      Riffer::Voice::Events::AudioChunk.new(payload: payload.to_s, mime_type: mime_type.to_s)
    end
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def extract_input_transcript(server_content)
    transcription = fetch_any(server_content, ["inputTranscription", "input_transcription"])
    transcript_event(transcription, klass: Riffer::Voice::Events::InputTranscript)
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def extract_output_transcript(server_content)
    transcription = fetch_any(server_content, ["outputTranscription", "output_transcription"])
    transcript_event(transcription, klass: Riffer::Voice::Events::OutputTranscript)
  end

  #: (untyped, klass: singleton(Riffer::Voice::Events::Base)) -> Array[Riffer::Voice::Events::Base]
  def transcript_event(transcription, klass:)
    return [] if transcription.nil?

    if transcription.is_a?(String)
      return [klass.new(text: transcription, metadata: {})]
    end

    return [] unless transcription.is_a?(Hash)

    text = fetch_any(transcription, ["text", "transcript"])
    return [] if text.nil? || text.to_s.empty?

    is_final = fetch_any(transcription, ["isFinal", "final", "finished"])
    metadata = symbolize_hash(transcription)
    [klass.new(text: text.to_s, is_final: is_final.nil? ? nil : is_final == true, metadata: metadata)]
  end

  #: (Hash[String, untyped], Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def extract_tool_calls(data, server_content)
    payload = fetch_any(data, ["toolCall", "tool_call"]) || fetch_any(server_content, ["toolCall", "tool_call"])
    return [] unless payload.is_a?(Hash)

    function_calls = Array(fetch_any(payload, ["functionCalls", "function_calls"]))
    function_calls = [payload] if function_calls.empty?

    function_calls.filter_map do |entry|
      next unless entry.is_a?(Hash)

      call = fetch_any(entry, ["functionCall", "function_call"]) || entry
      next unless call.is_a?(Hash)

      call_id = fetch_any(call, ["id", "callId", "call_id"])
      name = fetch_any(call, ["name", "functionName", "function_name"])
      arguments = fetch_any(call, ["args", "arguments"]) || {}
      next if call_id.nil? || name.nil?

      item_id = fetch_any(call, ["itemId", "item_id", "id"])
      Riffer::Voice::Events::ToolCall.new(
        call_id: call_id.to_s,
        name: name.to_s,
        arguments: arguments,
        item_id: item_id&.to_s
      )
    end
  end

  #: (Hash[String, untyped], Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def extract_interrupt(data, server_content)
    interrupted = true_any?(data, ["interrupted"]) || true_any?(server_content, ["interrupted"])
    return [] unless interrupted

    [Riffer::Voice::Events::Interrupt.new(reason: "interrupted")]
  end

  #: (Hash[String, untyped], Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def extract_turn_complete(data, server_content)
    turn_complete = true_any?(data, ["turnComplete", "turn_complete"]) ||
      true_any?(server_content, ["turnComplete", "turn_complete"])
    return [] unless turn_complete

    [Riffer::Voice::Events::TurnComplete.new(metadata: {})]
  end

  #: (Hash[String, untyped], Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def extract_usage(data, server_content)
    usage = fetch_any(data, ["usageMetadata", "usage_metadata", "usage"]) ||
      fetch_any(server_content, ["usageMetadata", "usage_metadata", "usage"])
    return [] unless usage.is_a?(Hash)

    input_tokens = fetch_any(usage, ["promptTokenCount", "inputTokens", "input_tokens"])
    output_tokens = fetch_any(usage, ["candidatesTokenCount", "outputTokens", "output_tokens"])
    input_audio_tokens = fetch_any(usage, ["inputAudioTokenCount", "inputAudioTokens", "input_audio_tokens"])
    output_audio_tokens = fetch_any(usage, ["outputAudioTokenCount", "outputAudioTokens", "output_audio_tokens"])

    return [] if [input_tokens, output_tokens, input_audio_tokens, output_audio_tokens].all?(&:nil?)

    [Riffer::Voice::Events::Usage.new(
      input_tokens: int_or_nil(input_tokens),
      output_tokens: int_or_nil(output_tokens),
      input_audio_tokens: int_or_nil(input_audio_tokens),
      output_audio_tokens: int_or_nil(output_audio_tokens),
      metadata: symbolize_hash(usage)
    )]
  end

  #: (untyped) -> Integer?
  def int_or_nil(value)
    return nil if value.nil?

    Integer(value)
  rescue
    nil
  end
end
