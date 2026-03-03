# frozen_string_literal: true
# rbs_inline: enabled

require "json"

# Parses Gemini Live realtime payloads into normalized voice events.
class Riffer::Voice::Parsers::GeminiLiveParser < Riffer::Voice::Parsers::Base
  KEYS_SERVER_CONTENT = ["serverContent", "server_content"].freeze #: Array[String]
  KEYS_MODEL_TURN = ["modelTurn", "model_turn"].freeze #: Array[String]
  KEYS_INLINE_DATA = ["inlineData", "inline_data"].freeze #: Array[String]
  KEYS_MIME_TYPE = ["mimeType", "mime_type"].freeze #: Array[String]
  KEYS_INPUT_TRANSCRIPTION = ["inputTranscription", "input_transcription"].freeze #: Array[String]
  KEYS_OUTPUT_TRANSCRIPTION = ["outputTranscription", "output_transcription"].freeze #: Array[String]
  KEYS_TEXT_TRANSCRIPT = ["text", "transcript"].freeze #: Array[String]
  KEYS_PARTS = ["parts"].freeze #: Array[String]
  KEYS_IS_FINAL = ["isFinal", "final", "finished"].freeze #: Array[String]
  KEYS_TOOL_CALL = ["toolCall", "tool_call"].freeze #: Array[String]
  KEYS_FUNCTION_CALLS = ["functionCalls", "function_calls"].freeze #: Array[String]
  KEYS_FUNCTION_CALL = ["functionCall", "function_call"].freeze #: Array[String]
  KEYS_CALL_ID = ["id", "callId", "call_id"].freeze #: Array[String]
  KEYS_NAME = ["name", "functionName", "function_name"].freeze #: Array[String]
  KEYS_ARGS = ["args", "arguments"].freeze #: Array[String]
  KEYS_ITEM_ID = ["itemId", "item_id", "id"].freeze #: Array[String]
  KEYS_TURN_COMPLETE = ["turnComplete", "turn_complete"].freeze #: Array[String]
  KEYS_USAGE = ["usageMetadata", "usage_metadata", "usage"].freeze #: Array[String]
  KEYS_INPUT_TOKENS = ["promptTokenCount", "inputTokens", "input_tokens"].freeze #: Array[String]
  KEYS_OUTPUT_TOKENS = ["candidatesTokenCount", "outputTokens", "output_tokens"].freeze #: Array[String]
  KEYS_INPUT_AUDIO_TOKENS = ["inputAudioTokenCount", "inputAudioTokens", "input_audio_tokens"].freeze #: Array[String]
  KEYS_OUTPUT_AUDIO_TOKENS = ["outputAudioTokenCount", "outputAudioTokens", "output_audio_tokens"].freeze #: Array[String]

  #: (Hash[Symbol | String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def call(payload)
    data = normalize_hash(payload)
    server_content = fetch_any(data, KEYS_SERVER_CONTENT)

    # Fast path: pure audio delta frames (most frequent during voice streaming).
    if audio_only_frame?(data, server_content)
      return extract_audio_chunk(server_content)
    end

    events = [] #: Array[Riffer::Voice::Events::Base]
    server_content ||= {}
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

  #: (Hash[String, untyped], Hash[String, untyped]?) -> bool
  def audio_only_frame?(data, server_content)
    return false unless server_content.is_a?(Hash)
    return false if true_any?(server_content, KEYS_TURN_COMPLETE)
    return false if data["interrupted"] == true || server_content["interrupted"] == true
    return false if data.key?("toolCall") || data.key?("tool_call")
    return false if data.key?("usageMetadata") || data.key?("usage_metadata") || data.key?("usage")

    model_turn = fetch_any(server_content, KEYS_MODEL_TURN)
    return false unless model_turn.is_a?(Hash)

    parts = Array(model_turn["parts"])
    return false if parts.empty?

    parts.all? do |part|
      next false unless part.is_a?(Hash)

      inline_data = fetch_any(part, KEYS_INLINE_DATA)
      inline_data.is_a?(Hash) && !inline_data["data"].to_s.empty?
    end
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def extract_audio_chunk(server_content)
    model_turn = fetch_any(server_content, KEYS_MODEL_TURN) || {}
    parts = Array(model_turn["parts"])

    parts.filter_map do |part|
      next unless part.is_a?(Hash)
      inline_data = fetch_any(part, KEYS_INLINE_DATA)
      next unless inline_data.is_a?(Hash)

      payload = inline_data["data"]
      next if payload.nil? || payload.to_s.empty?

      mime_type = fetch_any(inline_data, KEYS_MIME_TYPE) || "audio/pcm"
      Riffer::Voice::Events::AudioChunk.new(payload: payload.to_s, mime_type: mime_type.to_s)
    end
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def extract_input_transcript(server_content)
    transcription = fetch_any(server_content, KEYS_INPUT_TRANSCRIPTION)
    transcript_event(transcription, klass: Riffer::Voice::Events::InputTranscript)
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def extract_output_transcript(server_content)
    transcription = fetch_any(server_content, KEYS_OUTPUT_TRANSCRIPTION)
    transcript_event(transcription, klass: Riffer::Voice::Events::OutputTranscript)
  end

  #: (untyped, klass: singleton(Riffer::Voice::Events::Base)) -> Array[Riffer::Voice::Events::Base]
  def transcript_event(transcription, klass:)
    return [] if transcription.nil?

    if transcription.is_a?(String)
      return [klass.new(text: transcription, metadata: {})]
    end

    return [] unless transcription.is_a?(Hash)

    text = extract_transcription_text(transcription)
    return [] if text.nil? || text.to_s.empty?

    is_final = fetch_any(transcription, KEYS_IS_FINAL)
    metadata = symbolize_hash(transcription)
    [klass.new(text: text.to_s, is_final: is_final.nil? ? nil : is_final == true, metadata: metadata)]
  end

  #: (Hash[String, untyped]) -> String?
  def extract_transcription_text(transcription)
    text = fetch_any(transcription, KEYS_TEXT_TRANSCRIPT)
    return text.to_s if text.is_a?(String) && !text.empty?

    parts = fetch_any(transcription, KEYS_PARTS)
    return nil unless parts.is_a?(Array) && !parts.empty?

    value = parts.filter_map do |part|
      next unless part.is_a?(Hash)

      part_text = part["text"]
      part_text.to_s unless part_text.nil? || part_text.to_s.empty?
    end.join("\n")

    value.empty? ? nil : value
  end

  #: (Hash[String, untyped], Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def extract_tool_calls(data, server_content)
    payload = fetch_any(data, KEYS_TOOL_CALL) || fetch_any(server_content, KEYS_TOOL_CALL)
    return [] unless payload.is_a?(Hash)

    function_calls = Array(fetch_any(payload, KEYS_FUNCTION_CALLS))
    function_calls = [payload] if function_calls.empty?

    function_calls.filter_map do |entry|
      next unless entry.is_a?(Hash)

      call = fetch_any(entry, KEYS_FUNCTION_CALL) || entry
      next unless call.is_a?(Hash)

      call_id = fetch_any(call, KEYS_CALL_ID)
      name = fetch_any(call, KEYS_NAME)
      arguments = parse_arguments(fetch_any(call, KEYS_ARGS))
      next if call_id.nil? || name.nil?

      item_id = fetch_any(call, KEYS_ITEM_ID)
      Riffer::Voice::Events::ToolCall.new(
        call_id: call_id.to_s,
        name: name.to_s,
        arguments: arguments,
        item_id: item_id&.to_s
      )
    end
  end

  #: (untyped) -> Hash[String, untyped]
  def parse_arguments(arguments)
    return {} if arguments.nil?
    return deep_stringify(arguments) if arguments.is_a?(Hash)

    parsed = JSON.parse(arguments.to_s)
    unless parsed.is_a?(Hash)
      warn_invalid_tool_arguments("expected JSON object, got #{parsed.class}")
      return {}
    end

    deep_stringify(parsed)
  rescue JSON::ParserError => error
    warn_invalid_tool_arguments("json parse failed (#{error.class}: #{error.message})")
    {}
  end

  #: (String) -> void
  def warn_invalid_tool_arguments(reason)
    Warning.warn("[riffer] gemini parser normalized invalid tool arguments: #{reason}\n")
  end

  #: (Hash[String, untyped], Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def extract_interrupt(data, server_content)
    return [] unless data["interrupted"] == true || server_content["interrupted"] == true

    [Riffer::Voice::Events::Interrupt.new(reason: "interrupted")]
  end

  #: (Hash[String, untyped], Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def extract_turn_complete(data, server_content)
    turn_complete = true_any?(data, KEYS_TURN_COMPLETE) ||
      true_any?(server_content, KEYS_TURN_COMPLETE)
    return [] unless turn_complete

    [Riffer::Voice::Events::TurnComplete.new(metadata: {})]
  end

  #: (Hash[String, untyped], Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def extract_usage(data, server_content)
    usage = fetch_any(data, KEYS_USAGE) ||
      fetch_any(server_content, KEYS_USAGE)
    return [] unless usage.is_a?(Hash)

    input_tokens = fetch_any(usage, KEYS_INPUT_TOKENS)
    output_tokens = fetch_any(usage, KEYS_OUTPUT_TOKENS)
    input_audio_tokens = fetch_any(usage, KEYS_INPUT_AUDIO_TOKENS)
    output_audio_tokens = fetch_any(usage, KEYS_OUTPUT_AUDIO_TOKENS)

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
  rescue TypeError, ArgumentError
    nil
  end
end
