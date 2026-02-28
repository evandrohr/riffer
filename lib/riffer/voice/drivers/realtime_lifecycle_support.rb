# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::RealtimeLifecycleSupport
  private

  #: (already_connected_message: String, callbacks: Hash[Symbol, ^(Riffer::Voice::Events::Base) -> void], connect_error_code: String, reader_annotation: String) { () -> void } -> bool
  def connect_realtime!(already_connected_message:, callbacks:, connect_error_code:, reader_annotation:)
    raise Riffer::Error, already_connected_message if connected?

    reset_callbacks(callbacks)
    validate_configuration!
    task = ensure_async_task!(@task_resolver.call)
    yield
    mark_connected!
    @reader_task = task.async(annotation: reader_annotation) { read_loop }
    true
  rescue Riffer::ArgumentError
    raise
  rescue => error
    cleanup_connection
    emit_error(
      code: connect_error_code,
      message: error.message,
      retriable: true,
      metadata: {error_class: error.class.name}
    )
    raise
  end

  #: (close_error_code: String, reason: String?) { () -> void } -> void
  def close_realtime!(close_error_code:, reason:, &after_close)
    return if closed?

    mark_closed!
    stop_reader_task
    @transport&.close
    @transport = nil
    @reader_task = nil
    after_close&.call
    log_debug(reason: reason)
  rescue => error
    emit_error(
      code: close_error_code,
      message: error.message,
      retriable: false,
      metadata: {error_class: error.class.name}
    )
  end
end
