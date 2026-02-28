# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::OpenaiRealtimeConnection
  private

  #: () -> void
  def validate_configuration!
    raise Riffer::ArgumentError, "openai api_key is required" if @api_key.nil? || @api_key.empty?
    raise Riffer::ArgumentError, "openai realtime model is required" if model.nil? || model.empty?
  end

  #: () -> String
  def websocket_url
    "#{@endpoint}?model=#{CGI.escape(model)}"
  end

  #: () -> Hash[String, String]
  def websocket_headers
    {
      "Authorization" => "Bearer #{@api_key}"
    }
  end

  #: () -> void
  def read_loop
    while connected?
      transport = @transport
      break if transport.nil?

      frame = transport.read
      break if frame.nil?

      payload = parse_frame_payload(frame)
      next unless payload

      update_response_tracking(payload)
      parsed_events = @parser.call(payload)
      log_response_payload(payload: payload, parsed_events: parsed_events)
      log_unparsed_response_payload(payload) if parsed_events.empty?
      parsed_events.each { |event| emit_event(event) }
    end
  rescue => error
    emit_error(code: "openai_realtime_reader_failed", message: error.message, retriable: true, metadata: {error_class: error.class.name})
  ensure
    mark_disconnected!
  end

  #: (untyped) -> Hash[String, untyped]?
  def parse_frame_payload(frame)
    parse_json_frame_payload(frame: frame, invalid_json_code: "openai_realtime_invalid_json")
  end

  #: () -> void
  def stop_reader_task
    stop_async_task(@reader_task)
  end

  #: () -> void
  def cleanup_connection
    stop_reader_task
    @transport&.close
    @transport = nil
    @reader_task = nil
    with_response_state_lock { reset_response_tracking! }
    mark_disconnected!
  rescue
    nil
  end
end
