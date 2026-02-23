# frozen_string_literal: true
# rbs_inline: enabled

# Runtime strategy that reuses an existing Async task context.
class Riffer::Voice::Runtime::ManagedAsync
  # The current Async task.
  attr_reader :task #: untyped

  #: (task: untyped) -> void
  def initialize(task:)
    @task = task
  end

  #: () -> Symbol
  def kind
    :async
  end

  #: () -> bool
  def background?
    false
  end

  #: () -> bool
  def closed?
    false
  end

  #: () { () -> untyped } -> untyped
  def schedule(&block)
    raise Riffer::ArgumentError, "schedule requires a block" unless block

    if @task.respond_to?(:async)
      @task.async(annotation: "riffer-voice-runtime", &block)
    else
      block.call
    end
  end

  #: () -> bool
  def shutdown
    true
  end
end
