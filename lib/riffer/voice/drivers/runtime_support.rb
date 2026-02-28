# frozen_string_literal: true
# rbs_inline: enabled

require "json"

module Riffer::Voice::Drivers::RuntimeSupport
  private

  #: () -> ^(url: String, headers: Hash[String, String]) -> untyped
  def default_transport_factory
    ->(url:, headers:) { Riffer::Voice::Transports::AsyncWebsocket.connect(url: url, headers: headers) }
  end

  #: () -> ^() -> untyped
  def default_task_resolver
    -> {
      begin
        Async::Task.current
      rescue NameError, RuntimeError
        nil
      end
    }
  end

  #: (frame: untyped, invalid_json_code: String) -> Hash[String, untyped]?
  def parse_json_frame_payload(frame:, invalid_json_code:)
    raw_payload = extract_frame_payload(frame)
    return nil if raw_payload.nil? || raw_payload.to_s.empty?

    JSON.parse(raw_payload)
  rescue JSON::ParserError => error
    emit_error(code: invalid_json_code, message: error.message, retriable: true, metadata: {payload: raw_payload.to_s})
    nil
  end

  #: (untyped) -> void
  def stop_async_task(task)
    return if task.nil?

    task.stop if task.respond_to?(:stop)
  rescue
    nil
  end

  #: (error_code: String, failure_message: String, retriable: bool) { () -> void } -> void
  def with_driver_error_handling(error_code:, failure_message:, retriable: true)
    yield
  rescue => error
    emit_error(
      code: error_code,
      message: error.message,
      retriable: retriable,
      metadata: {error_class: error.class.name}
    )
    raise Riffer::Error, "#{failure_message}: #{error.class}: #{error.message}"
  end

  #: (untyped) -> String?
  def extract_frame_payload(frame)
    if frame.respond_to?(:to_str)
      frame.to_str
    elsif frame.respond_to?(:payload)
      frame.payload
    else
      frame.to_s
    end
  end
end
