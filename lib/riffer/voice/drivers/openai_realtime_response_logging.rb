# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::OpenaiRealtimeResponseLogging
  private

  #: (Hash[String, untyped]) -> void
  def log_unparsed_response_payload(payload)
    type = payload["type"].to_s
    return unless type.start_with?("response.")
    return unless @logger&.respond_to?(:debug)

    response = payload["response"].is_a?(Hash) ? payload["response"] : {}
    @logger.debug(
      type: self.class.name,
      event: "openai_realtime_unparsed_payload",
      payload_type: type,
      payload_keys: payload.keys,
      response_status: response["status"],
      response_status_details: response["status_details"]
    )
  rescue
    nil
  end

  #: (payload: Hash[String, untyped], parsed_events: Array[Riffer::Voice::Events::Base]) -> void
  def log_response_payload(payload:, parsed_events:)
    type = payload["type"].to_s
    return unless type.start_with?("response.")
    return unless @logger&.respond_to?(:debug)

    @logger.debug(
      type: self.class.name,
      event: "openai_realtime_response_payload",
      payload_type: type,
      parsed_events_count: parsed_events.length,
      parsed_event_types: parsed_events.map { |event| event.class.name }
    )
  rescue
    nil
  end
end
