# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Agent::EventLoop
  include Riffer::Voice::Agent::EventLoopSupport

  #: (?timeout: Numeric?, ?auto_handle_tool_calls: bool) -> Riffer::Voice::Events::Base?
  def next_event(timeout: nil, auto_handle_tool_calls: @auto_handle_tool_calls)
    event = current_session.next_event(timeout: timeout)
    return nil if event.nil?

    consume_event(event, auto_handle_tool_calls: auto_handle_tool_calls)
  end

  #: (?auto_handle_tool_calls: bool) -> Enumerator[Riffer::Voice::Events::Base, void]
  def events(auto_handle_tool_calls: @auto_handle_tool_calls)
    Enumerator.new do |yielder|
      current_session.events.each do |event|
        yielder << consume_event(event, auto_handle_tool_calls: auto_handle_tool_calls)
      end
    end
  end

  # Runs an event loop and yields events until a stop condition is reached.
  #
  # Stop conditions:
  # - timeout reached (when timeout is provided)
  # - no event is returned within remaining timeout
  # - agent becomes closed/disconnected
  # - interrupt event is received
  #
  #: (?timeout: Numeric?, ?auto_handle_tool_calls: bool) { (Riffer::Voice::Events::Base) -> void } -> self
  def run_loop(timeout: nil, auto_handle_tool_calls: @auto_handle_tool_calls, &block)
    validate_timeout!(timeout)
    return enum_for(:run_loop, timeout: timeout, auto_handle_tool_calls: auto_handle_tool_calls) unless block_given?

    deadline = loop_deadline(timeout)

    loop do
      event = poll_loop_event(deadline: deadline, auto_handle_tool_calls: auto_handle_tool_calls)
      break if event.nil?

      yield event
      break if event.is_a?(Riffer::Voice::Events::Interrupt)
    end

    self
  end

  # Sends optional input text and consumes events until turn completion or stop.
  #
  #: (?text: String?, ?timeout: Numeric?, ?auto_handle_tool_calls: bool) -> Array[Riffer::Voice::Events::Base]
  def run_until_turn_complete(text: nil, timeout: nil, auto_handle_tool_calls: @auto_handle_tool_calls)
    validate_timeout!(timeout)
    send_text_turn(text: text) unless text.nil?

    collected = []
    deadline = loop_deadline(timeout)

    loop do
      event = poll_loop_event(deadline: deadline, auto_handle_tool_calls: auto_handle_tool_calls)
      break if event.nil?

      collected << event
      break if stop_on_turn_complete?(event)
    end

    collected
  end

  # Drains currently available events without blocking.
  #
  #: (?max_events: Integer?, ?auto_handle_tool_calls: bool) -> Array[Riffer::Voice::Events::Base]
  def drain_available_events(max_events: nil, auto_handle_tool_calls: @auto_handle_tool_calls)
    validate_max_events!(max_events)

    drained = []
    loop do
      break if reached_event_drain_limit?(drained, max_events)

      event = next_event(timeout: 0, auto_handle_tool_calls: auto_handle_tool_calls)
      break if event.nil?

      drained << event
    end

    drained
  end

  private

  #: (Riffer::Voice::Events::Base, auto_handle_tool_calls: bool) -> Riffer::Voice::Events::Base
  def consume_event(event, auto_handle_tool_calls:)
    handle_tool_call_event(event) if auto_handle_tool_calls
    dispatch_event_callbacks(event)
    emit_checkpoint(:turn_complete, {event: event}) if event.is_a?(Riffer::Voice::Events::TurnComplete)
    event
  end
end
