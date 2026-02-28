# frozen_string_literal: true
# rbs_inline: enabled

# Response lifecycle, interrupt, and error extraction for OpenAI realtime payloads.
module Riffer::Voice::Parsers::OpenaiRealtimeParserResponse
  include Riffer::Voice::Parsers::OpenaiRealtimeParserConstants

  private

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_response_done(data)
    response = hash_or_empty(data["response"])
    usage = hash_or_empty(response["usage"])
    status = response["status"].to_s
    status_details = hash_or_empty(response["status_details"])

    events = [] #: Array[Riffer::Voice::Events::Base]
    events.concat(response_done_error_events(status: status, status_details: status_details, response: response))

    usage_event = usage_done_event(usage)
    events << usage_event unless usage_event.nil?

    events << Riffer::Voice::Events::TurnComplete.new(metadata: symbolize_hash(response))
    events
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_error(data)
    error = hash_or_empty(data["error"]).empty? ? data : hash_or_empty(data["error"])
    code = (fetch_any(error, KEYS_ERROR_CODE) || "provider_error").to_s

    [Riffer::Voice::Events::Error.new(
      code: code,
      message: (error["message"] || "Provider realtime error").to_s,
      retriable: retriable_error?(code),
      metadata: symbolize_hash(error)
    )]
  end

  #: (type: String) -> Array[Riffer::Voice::Events::Base]
  def parse_interrupt(type:)
    return [] unless INTERRUPT_TYPES.include?(type)

    [Riffer::Voice::Events::Interrupt.new(reason: type)]
  end

  #: (status: String, status_details: Hash[String, untyped], response: Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def response_done_error_events(status:, status_details:, response:)
    return [] unless response_status_error?(status)

    [Riffer::Voice::Events::Error.new(
      code: response_done_error_code(status: status, status_details: status_details),
      message: response_done_error_message(status: status, status_details: status_details),
      retriable: retriable_error?(status_details.dig("error", "code").to_s),
      metadata: symbolize_hash(response)
    )]
  end

  #: (Hash[String, untyped]) -> Riffer::Voice::Events::Usage?
  def usage_done_event(usage)
    return nil if usage.empty?

    Riffer::Voice::Events::Usage.new(
      input_tokens: int_or_nil(fetch_any(usage, KEYS_INPUT_TOKENS)),
      output_tokens: int_or_nil(fetch_any(usage, KEYS_OUTPUT_TOKENS)),
      input_audio_tokens: int_or_nil(fetch_any(usage, KEYS_INPUT_AUDIO_TOKENS)),
      output_audio_tokens: int_or_nil(fetch_any(usage, KEYS_OUTPUT_AUDIO_TOKENS)),
      metadata: symbolize_hash(usage)
    )
  end

  #: (String) -> bool
  def response_status_error?(status)
    normalized_status = status.downcase
    return false if normalized_status.empty? || normalized_status == "completed"
    return false if NON_ERROR_RESPONSE_STATUSES.include?(normalized_status)

    true
  end

  #: (status: String, status_details: Hash[String, untyped]) -> String
  def response_done_error_code(status:, status_details:)
    explicit_code = fetch_any(status_details, KEYS_STATUS_DETAILS_CODE) || status_details.dig("error", "code")
    return explicit_code.to_s unless explicit_code.to_s.empty?

    "response_#{status}"
  end

  #: (status: String, status_details: Hash[String, untyped]) -> String
  def response_done_error_message(status:, status_details:)
    explicit_message = status_details["message"] || status_details.dig("error", "message")
    return explicit_message.to_s unless explicit_message.to_s.empty?

    "Response finished with status: #{status}"
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

  #: (untyped) -> Hash[String, untyped]
  def hash_or_empty(value)
    value.is_a?(Hash) ? value : {}
  end
end
