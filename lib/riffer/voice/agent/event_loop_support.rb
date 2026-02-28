# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Agent::EventLoopSupport
  private

  #: (Numeric?) -> void
  def validate_timeout!(timeout)
    invalid_timeout = !timeout.nil? && (!timeout.is_a?(Numeric) || timeout < 0)
    raise Riffer::ArgumentError, "timeout must be nil or >= 0" if invalid_timeout
  end

  #: (Integer?) -> void
  def validate_max_events!(max_events)
    invalid_max_events = !max_events.nil? && (!max_events.is_a?(Integer) || max_events <= 0)
    raise Riffer::ArgumentError, "max_events must be nil or an Integer > 0" if invalid_max_events
  end

  #: (Numeric?) -> Float?
  def loop_deadline(timeout)
    return nil if timeout.nil?

    monotonic_time + timeout
  end

  #: (deadline: Float?, auto_handle_tool_calls: bool) -> Riffer::Voice::Events::Base?
  def poll_loop_event(deadline:, auto_handle_tool_calls:)
    return nil if closed? || !connected?

    next_timeout = remaining_timeout(deadline)
    return nil if timeout_reached?(deadline, next_timeout)

    next_event(timeout: next_timeout, auto_handle_tool_calls: auto_handle_tool_calls)
  end

  #: (Float?, Numeric?) -> bool
  def timeout_reached?(deadline, next_timeout)
    !deadline.nil? && next_timeout <= 0
  end

  #: (Riffer::Voice::Events::Base) -> bool
  def stop_on_turn_complete?(event)
    event.is_a?(Riffer::Voice::Events::TurnComplete) || event.is_a?(Riffer::Voice::Events::Interrupt)
  end

  #: (Array[Riffer::Voice::Events::Base], Integer?) -> bool
  def reached_event_drain_limit?(drained, max_events)
    !max_events.nil? && drained.length >= max_events
  end
end
