# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::OpenaiRealtimeResponseState
  include Riffer::Voice::Drivers::OpenaiRealtimeResponseFlow
  include Riffer::Voice::Drivers::OpenaiRealtimeResponseLogging

  private

  #: () -> Hash[String, untyped]
  def response_create_payload
    Riffer::Voice::Drivers::OpenAIRealtime::RESPONSE_CREATE_PAYLOAD
  end

  #: () -> void
  def reset_response_tracking!
    @response_in_progress = false
    @response_create_pending = false
    @response_create_in_flight = false
  end

  #: () { () -> untyped } -> untyped
  def with_response_state_lock
    @response_state_lock.synchronize { yield }
  end
end
