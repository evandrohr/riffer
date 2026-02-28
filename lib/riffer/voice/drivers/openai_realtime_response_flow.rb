# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::OpenaiRealtimeResponseFlow
  private

  #: () -> void
  def request_response_create
    should_send = false
    with_response_state_lock do
      if @response_in_progress
        @response_create_pending = true
      else
        @response_in_progress = true
        @response_create_in_flight = true
        @response_create_pending = false
        should_send = true
      end
    end

    return unless should_send

    @transport.write_json(response_create_payload)
  rescue => error
    with_response_state_lock do
      @response_create_in_flight = false
      @response_in_progress = false
    end
    raise error
  end

  #: (Hash[String, untyped]) -> void
  def update_response_tracking(payload)
    type = payload["type"].to_s
    should_flush = false
    with_response_state_lock do
      case type
      when "response.created", "response.in_progress"
        @response_create_in_flight = false
        @response_in_progress = true
      when "response.done", "response.completed", "response.cancelled", "response.canceled", "response.failed"
        @response_create_in_flight = false
        @response_in_progress = false
        should_flush = @response_create_pending
      when "error"
        should_flush = update_response_tracking_from_error_unlocked(payload)
      end
    end

    flush_pending_response_create if should_flush
  rescue
    nil
  end

  #: (Hash[String, untyped]) -> void
  def update_response_tracking_from_error_unlocked(payload)
    error_payload = payload["error"].is_a?(Hash) ? payload["error"] : {}
    code = (error_payload["code"] || error_payload["type"] || "").to_s
    if code == "conversation_already_has_active_response"
      @response_create_in_flight = false
      @response_in_progress = true
      @response_create_pending = true
      return false
    end

    return false unless @response_create_in_flight

    @response_create_in_flight = false
    @response_in_progress = false
    @response_create_pending
  end

  #: () -> void
  def flush_pending_response_create
    should_send = false
    with_response_state_lock do
      return unless @response_create_pending
      return unless connected?
      return if @response_in_progress

      @response_in_progress = true
      @response_create_in_flight = true
      @response_create_pending = false
      should_send = true
    end

    return unless should_send

    @transport.write_json(response_create_payload)
  rescue => error
    with_response_state_lock do
      @response_in_progress = false
      @response_create_in_flight = false
      @response_create_pending = true if connected?
    end
    emit_error(
      code: "openai_realtime_send_response_create_failed",
      message: error.message,
      retriable: true,
      metadata: {error_class: error.class.name}
    )
  end
end
