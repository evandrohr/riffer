# frozen_string_literal: true
# rbs_inline: enabled

require "json"

# Parses OpenAI Realtime GA payloads into normalized voice events.
class Riffer::Voice::Parsers::OpenAIRealtimeParser < Riffer::Voice::Parsers::Base
  INTERRUPT_TYPES = [
    "input_audio_buffer.speech_started",
    "response.interrupted",
    "response.cancelled"
  ].freeze #: Array[String]

  #: (Hash[Symbol | String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def call(payload)
    data = normalize_hash(payload)
    type = data["type"]
    return [] if type.nil? || type.empty?

    case type
    when "response.output_audio.delta"
      parse_audio_delta(data)
    when "conversation.item.input_audio_transcription.delta"
      parse_input_transcript(data, is_final: false)
    when "conversation.item.input_audio_transcription.completed", "conversation.item.input_audio_transcription.done"
      parse_input_transcript(data, is_final: true)
    when "response.output_audio_transcript.delta"
      parse_output_transcript(data, is_final: false)
    when "response.output_audio_transcript.done"
      parse_output_transcript(data, is_final: true)
    when "response.function_call_arguments.done"
      parse_tool_call(data)
    when "response.done"
      parse_response_done(data)
    when "error"
      parse_error(data)
    else
      parse_interrupt(data, type: type)
    end
  end

  private

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_audio_delta(data)
    payload = data["delta"]
    return [] if payload.nil? || payload.to_s.empty?

    mime_type = fetch_any(data, ["mime_type", "mimeType"]) || "audio/pcm"
    [Riffer::Voice::Events::AudioChunk.new(payload: payload.to_s, mime_type: mime_type.to_s)]
  end

  #: (Hash[String, untyped], is_final: bool) -> Array[Riffer::Voice::Events::Base]
  def parse_input_transcript(data, is_final:)
    text = fetch_any(data, ["delta", "transcript", "text"])
    return [] if text.nil? || text.to_s.empty?

    [Riffer::Voice::Events::InputTranscript.new(text: text.to_s, is_final: is_final, metadata: symbolize_hash(data))]
  end

  #: (Hash[String, untyped], is_final: bool) -> Array[Riffer::Voice::Events::Base]
  def parse_output_transcript(data, is_final:)
    text = fetch_any(data, ["delta", "transcript", "text"])
    return [] if text.nil? || text.to_s.empty?

    [Riffer::Voice::Events::OutputTranscript.new(text: text.to_s, is_final: is_final, metadata: symbolize_hash(data))]
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_tool_call(data)
    call_id = fetch_any(data, ["call_id", "callId", "item_id", "itemId"])
    name = data["name"]
    arguments = parse_arguments(data["arguments"])
    return [] if call_id.nil? || name.nil?

    [Riffer::Voice::Events::ToolCall.new(
      call_id: call_id.to_s,
      item_id: fetch_any(data, ["item_id", "itemId"])&.to_s,
      name: name.to_s,
      arguments: arguments
    )]
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_response_done(data)
    response = data["response"].is_a?(Hash) ? data["response"] : {}
    usage = response["usage"].is_a?(Hash) ? response["usage"] : {}

    events = [] #: Array[Riffer::Voice::Events::Base]
    unless usage.empty?
      events << Riffer::Voice::Events::Usage.new(
        input_tokens: int_or_nil(fetch_any(usage, ["input_tokens", "inputTokens"])),
        output_tokens: int_or_nil(fetch_any(usage, ["output_tokens", "outputTokens"])),
        input_audio_tokens: int_or_nil(fetch_any(usage, ["input_audio_tokens", "inputAudioTokens"])),
        output_audio_tokens: int_or_nil(fetch_any(usage, ["output_audio_tokens", "outputAudioTokens"])),
        metadata: symbolize_hash(usage)
      )
    end

    events << Riffer::Voice::Events::TurnComplete.new(metadata: symbolize_hash(response))
    events
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_error(data)
    error = data["error"].is_a?(Hash) ? data["error"] : data
    code = fetch_any(error, ["code", "type"]) || "provider_error"
    message = error["message"] || "Provider realtime error"
    retriable = retriable_error?(code.to_s)

    [Riffer::Voice::Events::Error.new(
      code: code.to_s,
      message: message.to_s,
      retriable: retriable,
      metadata: symbolize_hash(error)
    )]
  end

  #: (Hash[String, untyped], type: String) -> Array[Riffer::Voice::Events::Base]
  def parse_interrupt(data, type:)
    return [] unless INTERRUPT_TYPES.include?(type)

    [Riffer::Voice::Events::Interrupt.new(reason: type)]
  end

  #: (untyped) -> (String | Hash[Symbol | String, untyped])
  def parse_arguments(arguments)
    return {} if arguments.nil?
    return arguments if arguments.is_a?(Hash)

    JSON.parse(arguments)
  rescue JSON::ParserError
    arguments.to_s
  end

  #: (String) -> bool
  def retriable_error?(code)
    ["server_error", "rate_limit_exceeded", "overloaded_error"].include?(code)
  end

  #: (untyped) -> Integer?
  def int_or_nil(value)
    return nil if value.nil?

    Integer(value)
  rescue
    nil
  end
end
