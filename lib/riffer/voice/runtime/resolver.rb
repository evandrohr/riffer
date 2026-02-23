# frozen_string_literal: true
# rbs_inline: enabled

# Resolves runtime mode into a concrete runtime strategy object.
class Riffer::Voice::Runtime::Resolver
  #: (requested_mode: Symbol, ?task_resolver: ^() -> untyped) -> (Riffer::Voice::Runtime::ManagedAsync | Riffer::Voice::Runtime::BackgroundAsync)
  def self.resolve(requested_mode:, task_resolver: nil)
    task_resolver ||= method(:default_task).to_proc

    case requested_mode
    when :async
      task = task_resolver.call
      raise Riffer::ArgumentError, "runtime :async requires an active Async task context" unless task

      Riffer::Voice::Runtime::ManagedAsync.new(task: task)
    when :background
      Riffer::Voice::Runtime::BackgroundAsync.new
    when :auto
      task = task_resolver.call
      return Riffer::Voice::Runtime::ManagedAsync.new(task: task) if task

      Riffer::Voice::Runtime::BackgroundAsync.new
    else
      raise Riffer::ArgumentError, "Unsupported runtime mode: #{requested_mode}"
    end
  end

  #: () -> untyped
  def self.default_task
    Async::Task.current
  rescue NameError, RuntimeError
    nil
  end
  private_class_method :default_task
end
