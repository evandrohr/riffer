# frozen_string_literal: true
# rbs_inline: enabled

require "json"

# Parses OpenAI Realtime GA payloads into normalized voice events.
class Riffer::Voice::Parsers::OpenAIRealtimeParser < Riffer::Voice::Parsers::Base
  DEFAULT_AUDIO_MIME_TYPE = "audio/pcm;rate=24000" #: String
  NON_ERROR_RESPONSE_STATUSES = ["cancelled", "canceled"].freeze #: Array[String]

  INTERRUPT_TYPES = [
    "input_audio_buffer.speech_started",
    "response.interrupted",
    "response.cancelled"
  ].freeze #: Array[String]

  KEYS_DELTA_PAYLOAD = ["delta", "audio", "data"].freeze #: Array[String]
  KEYS_PART_AUDIO = ["audio", "delta", "data"].freeze #: Array[String]
  KEYS_MIME_TYPE = ["mime_type", "mimeType"].freeze #: Array[String]
  KEYS_DELTA_TEXT = ["delta", "transcript", "text"].freeze #: Array[String]
  KEYS_TRANSCRIPT_TEXT = ["transcript", "text"].freeze #: Array[String]
  KEYS_CALL_ID = ["call_id", "callId", "item_id", "itemId"].freeze #: Array[String]
  KEYS_ITEM_ID = ["item_id", "itemId"].freeze #: Array[String]
  KEYS_ENTITY_ID = ["id", "item_id", "itemId"].freeze #: Array[String]
  KEYS_ERROR_CODE = ["code", "type"].freeze #: Array[String]
  KEYS_INPUT_TOKENS = ["input_tokens", "inputTokens"].freeze #: Array[String]
  KEYS_OUTPUT_TOKENS = ["output_tokens", "outputTokens"].freeze #: Array[String]
  KEYS_INPUT_AUDIO_TOKENS = ["input_audio_tokens", "inputAudioTokens"].freeze #: Array[String]
  KEYS_OUTPUT_AUDIO_TOKENS = ["output_audio_tokens", "outputAudioTokens"].freeze #: Array[String]
  KEYS_STATUS_DETAILS_CODE = ["code", "type"].freeze #: Array[String]

  AUDIO_PART_TYPES = ["audio", "output_audio"].freeze #: Array[String]
  TRANSCRIPT_PART_TYPES = ["audio", "output_audio", "text", "output_text"].freeze #: Array[String]

  RETRIABLE_ERROR_CODES = ["server_error", "rate_limit_exceeded", "overloaded_error"].freeze #: Array[String]

  #: (Hash[Symbol | String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def call(payload)
    data = normalize_hash(payload)
    type = data["type"]
    return [] if type.nil? || type.empty?

    case type
    when "response.output_audio.delta", "response.audio.delta", "response.output_audio.done", "response.audio.done"
      parse_audio_delta(data)
    when "conversation.item.input_audio_transcription.delta"
      parse_input_transcript(data, is_final: false)
    when "conversation.item.input_audio_transcription.completed", "conversation.item.input_audio_transcription.done"
      parse_input_transcript(data, is_final: true)
    when "response.output_audio_transcript.delta", "response.audio_transcript.delta", "response.output_text.delta", "response.text.delta"
      parse_output_transcript(data, is_final: false)
    when "response.output_audio_transcript.done", "response.audio_transcript.done", "response.output_text.done", "response.text.done"
      parse_output_transcript(data, is_final: true)
    when "response.content_part.added"
      parse_content_part(data, is_final: false)
    when "response.content_part.done"
      parse_content_part(data, is_final: true)
    when "response.function_call_arguments.done"
      parse_tool_call(data)
    when "response.output_item.added", "response.output_item.done"
      parse_output_item(data)
    when "response.done"
      parse_response_done(data)
    when "error"
      parse_error(data)
    else
      parse_interrupt(data, type: type)
    end
  end

  private

  #: (Hash[String, untyped], is_final: bool) -> Array[Riffer::Voice::Events::Base]
  def parse_content_part(data, is_final:)
    part = data["part"]
    return [] unless part.is_a?(Hash)

    part_type = part["type"].to_s
    events = [] #: Array[Riffer::Voice::Events::Base]

    if AUDIO_PART_TYPES.include?(part_type)
      audio_payload = fetch_any(part, KEYS_PART_AUDIO)
      unless audio_payload.nil? || audio_payload.to_s.empty?
        mime_type = fetch_any(part, KEYS_MIME_TYPE) || DEFAULT_AUDIO_MIME_TYPE
        events << Riffer::Voice::Events::AudioChunk.new(payload: audio_payload.to_s, mime_type: mime_type.to_s)
      end
    end

    text_payload = fetch_any(part, KEYS_TRANSCRIPT_TEXT)
    if !text_payload.nil? && !text_payload.to_s.empty? && TRANSCRIPT_PART_TYPES.include?(part_type)
      events << Riffer::Voice::Events::OutputTranscript.new(
        text: text_payload.to_s,
        is_final: is_final,
        metadata: symbolize_hash(part)
      )
    end

    events
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_audio_delta(data)
    payload = fetch_any(data, KEYS_DELTA_PAYLOAD)
    return [] if payload.nil? || payload.to_s.empty?

    mime_type = fetch_any(data, KEYS_MIME_TYPE) || DEFAULT_AUDIO_MIME_TYPE
    [Riffer::Voice::Events::AudioChunk.new(payload: payload.to_s, mime_type: mime_type.to_s)]
  end

  #: (Hash[String, untyped], is_final: bool) -> Array[Riffer::Voice::Events::Base]
  def parse_input_transcript(data, is_final:)
    text = fetch_any(data, KEYS_DELTA_TEXT)
    return [] if text.nil? || text.to_s.empty?

    [Riffer::Voice::Events::InputTranscript.new(text: text.to_s, is_final: is_final, metadata: symbolize_hash(data))]
  end

  #: (Hash[String, untyped], is_final: bool) -> Array[Riffer::Voice::Events::Base]
  def parse_output_transcript(data, is_final:)
    text = fetch_any(data, KEYS_DELTA_TEXT)
    return [] if text.nil? || text.to_s.empty?

    [Riffer::Voice::Events::OutputTranscript.new(text: text.to_s, is_final: is_final, metadata: symbolize_hash(data))]
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_tool_call(data)
    call_id = fetch_any(data, KEYS_CALL_ID)
    name = data["name"]
    arguments = parse_arguments(data["arguments"])
    return [] if call_id.nil? || name.nil?

    [Riffer::Voice::Events::ToolCall.new(
      call_id: call_id.to_s,
      item_id: fetch_any(data, KEYS_ITEM_ID)&.to_s,
      name: name.to_s,
      arguments: arguments
    )]
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_output_item(data)
    item = data["item"]
    return [] unless item.is_a?(Hash)

    item_type = item["type"].to_s
    case item_type
    when "function_call"
      []
    when "message"
      parse_output_item_message(item, is_final: data["type"] == "response.output_item.done")
    else
      []
    end
  end

  #: (Hash[String, untyped], is_final: bool) -> Array[Riffer::Voice::Events::Base]
  def parse_output_item_message(item, is_final:)
    content = item["content"]
    return [] unless content.is_a?(Array)

    content.each_with_object([]) do |part, events|
      next unless part.is_a?(Hash)

      part_type = part["type"].to_s
      if AUDIO_PART_TYPES.include?(part_type)
        audio_payload = fetch_any(part, KEYS_PART_AUDIO)
        if audio_payload && !audio_payload.to_s.empty?
          mime_type = fetch_any(part, KEYS_MIME_TYPE) || DEFAULT_AUDIO_MIME_TYPE
          events << Riffer::Voice::Events::AudioChunk.new(payload: audio_payload.to_s, mime_type: mime_type.to_s)
        end
      end

      transcript = fetch_any(part, KEYS_TRANSCRIPT_TEXT)
      if transcript && !transcript.to_s.empty? && TRANSCRIPT_PART_TYPES.include?(part_type)
        events << Riffer::Voice::Events::OutputTranscript.new(
          text: transcript.to_s,
          is_final: is_final,
          metadata: symbolize_hash(part)
        )
      end
    end
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_response_done(data)
    response = data["response"].is_a?(Hash) ? data["response"] : {}
    usage = response["usage"].is_a?(Hash) ? response["usage"] : {}
    status = response["status"].to_s
    status_details = response["status_details"].is_a?(Hash) ? response["status_details"] : {}

    events = [] #: Array[Riffer::Voice::Events::Base]
    if response_status_error?(status)
      events << Riffer::Voice::Events::Error.new(
        code: response_done_error_code(status: status, status_details: status_details),
        message: response_done_error_message(status: status, status_details: status_details),
        retriable: retriable_error?(status_details.dig("error", "code").to_s),
        metadata: symbolize_hash(response)
      )
    end

    unless usage.empty?
      events << Riffer::Voice::Events::Usage.new(
        input_tokens: int_or_nil(fetch_any(usage, KEYS_INPUT_TOKENS)),
        output_tokens: int_or_nil(fetch_any(usage, KEYS_OUTPUT_TOKENS)),
        input_audio_tokens: int_or_nil(fetch_any(usage, KEYS_INPUT_AUDIO_TOKENS)),
        output_audio_tokens: int_or_nil(fetch_any(usage, KEYS_OUTPUT_AUDIO_TOKENS)),
        metadata: symbolize_hash(usage)
      )
    end

    events << Riffer::Voice::Events::TurnComplete.new(metadata: symbolize_hash(response))
    events
  end

  #: (String) -> bool
  def response_status_error?(status)
    normalized_status = status.to_s.downcase
    return false if normalized_status.empty? || normalized_status == "completed"
    return false if NON_ERROR_RESPONSE_STATUSES.include?(normalized_status)

    true
  end

  #: (status: String, status_details: Hash[String, untyped]) -> String
  def response_done_error_code(status:, status_details:)
    explicit_code = fetch_any(status_details, KEYS_STATUS_DETAILS_CODE) || status_details.dig("error", "code")
    return explicit_code.to_s unless explicit_code.nil? || explicit_code.to_s.empty?

    "response_#{status}"
  end

  #: (status: String, status_details: Hash[String, untyped]) -> String
  def response_done_error_message(status:, status_details:)
    explicit_message = status_details["message"] || status_details.dig("error", "message")
    return explicit_message.to_s unless explicit_message.nil? || explicit_message.to_s.empty?

    "Response finished with status: #{status}"
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_error(data)
    error = data["error"].is_a?(Hash) ? data["error"] : data
    code = fetch_any(error, KEYS_ERROR_CODE) || "provider_error"
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

  #: (untyped) -> Hash[String, untyped]
  def parse_arguments(arguments)
    return {} if arguments.nil?
    return deep_stringify(arguments) if arguments.is_a?(Hash)

    parsed = JSON.parse(arguments)
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
    Warning.warn("[riffer] openai realtime parser normalized invalid tool arguments: #{reason}\n")
  end

  #: (String) -> bool
  def retriable_error?(code)
    RETRIABLE_ERROR_CODES.include?(code)
  end

  #: (untyped) -> Integer?
  def int_or_nil(value)
    return nil if value.nil?

    Integer(value)
  rescue TypeError, ArgumentError
    nil
  end
end
