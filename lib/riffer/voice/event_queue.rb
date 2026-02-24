# frozen_string_literal: true
# rbs_inline: enabled

# Thread-safe queue for voice events with timeout and close semantics.
class Riffer::Voice::EventQueue
  DEFAULT_FIBER_POLL_INTERVAL = 0.01 #: Float

  #: (?mode: Symbol, ?fiber_poll_interval: Numeric) -> void
  def initialize(mode: :thread, fiber_poll_interval: DEFAULT_FIBER_POLL_INTERVAL)
    invalid_poll_interval = !fiber_poll_interval.is_a?(Numeric) || fiber_poll_interval <= 0
    raise Riffer::ArgumentError, "fiber_poll_interval must be > 0" if invalid_poll_interval

    @mode = mode
    @fiber_poll_interval = fiber_poll_interval
    @events = [] #: Array[Riffer::Voice::Events::Base]
    @closed = false
    @mutex = Mutex.new
    @condition = ConditionVariable.new
  end

  #: (Riffer::Voice::Events::Base) -> bool
  def push(event)
    @mutex.synchronize do
      return false if @closed

      @events << event
      @condition.signal
      true
    end
  end

  #: (?timeout: Numeric?) -> Riffer::Voice::Events::Base?
  def pop(timeout: nil)
    return pop_fiber(timeout: timeout) if @mode == :fiber

    pop_thread(timeout: timeout)
  end

  #: () -> bool
  def close
    @mutex.synchronize do
      return true if @closed

      @closed = true
      @condition.broadcast
      true
    end
  end

  #: () -> bool
  def closed?
    @mutex.synchronize { @closed }
  end

  private

  #: (?timeout: Numeric?) -> Riffer::Voice::Events::Base?
  def pop_thread(timeout:)
    @mutex.synchronize do
      return @events.shift unless @events.empty?
      return nil if @closed

      deadline = timeout.nil? ? nil : monotonic_now + timeout
      loop do
        wait_for_event(deadline)
        return @events.shift unless @events.empty?
        return nil if @closed
        return nil if deadline && monotonic_now >= deadline
      end
    end
  end

  #: (?timeout: Numeric?) -> Riffer::Voice::Events::Base?
  def pop_fiber(timeout:)
    deadline = timeout.nil? ? nil : monotonic_now + timeout

    loop do
      event, closed = @mutex.synchronize do
        [@events.shift, @closed]
      end

      return event if event
      return nil if closed
      return nil if deadline && monotonic_now >= deadline

      if deadline
        remaining = deadline - monotonic_now
        sleep([remaining, @fiber_poll_interval].min) if remaining > 0
      else
        sleep(@fiber_poll_interval)
      end
    end
  end

  #: (Numeric?) -> void
  def wait_for_event(deadline)
    if deadline
      remaining = deadline - monotonic_now
      return if remaining <= 0

      @condition.wait(@mutex, remaining)
    else
      @condition.wait(@mutex)
    end
  end

  #: () -> Float
  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
