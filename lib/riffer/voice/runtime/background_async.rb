# frozen_string_literal: true
# rbs_inline: enabled

# Runtime strategy that manages a background worker thread.
class Riffer::Voice::Runtime::BackgroundAsync
  SHUTDOWN_SIGNAL = Object.new.freeze #: Object

  # Background worker thread.
  attr_reader :thread #: Thread

  #: () -> void
  def initialize
    @queue = Queue.new #: Queue[untyped]
    @closed = false
    @thread = Thread.new { run_loop }
  end

  #: () -> Symbol
  def kind
    :background
  end

  #: () -> bool
  def background?
    true
  end

  #: () -> bool
  def closed?
    @closed == true
  end

  #: () { () -> untyped } -> bool
  def schedule(&block)
    raise Riffer::ArgumentError, "schedule requires a block" unless block
    raise Riffer::Error, "background runtime is closed" if closed?

    @queue << block
    true
  end

  #: () -> bool
  def shutdown
    return true if closed?

    @closed = true
    @queue << SHUTDOWN_SIGNAL
    @thread.join
    true
  end

  private

  #: () -> void
  def run_loop
    loop do
      item = @queue.pop
      break if item.equal?(SHUTDOWN_SIGNAL)

      item.call
    rescue
      # Swallow worker exceptions in this phase.
      nil
    end
  end
end
