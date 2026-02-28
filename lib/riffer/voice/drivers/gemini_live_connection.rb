# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::GeminiLiveConnection
  private

  #: () -> void
  def validate_configuration!
    raise Riffer::ArgumentError, "gemini api_key is required" if @api_key.nil? || @api_key.empty?
    raise Riffer::ArgumentError, "gemini model is required" if model.nil? || model.empty?
  end

  #: () -> String
  def websocket_url
    # Gemini Live requires API key authentication via query parameter.
    "#{@endpoint}?key=#{CGI.escape(@api_key)}"
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

      @parser.call(payload).each { |event| emit_event(event) }
    end
  rescue => error
    emit_error(code: "gemini_reader_failed", message: error.message, retriable: true, metadata: {error_class: error.class.name})
  ensure
    mark_disconnected!
  end

  #: (untyped) -> Hash[String, untyped]?
  def parse_frame_payload(frame)
    parse_json_frame_payload(frame: frame, invalid_json_code: "gemini_invalid_json")
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
    mark_disconnected!
  rescue
    nil
  end
end
