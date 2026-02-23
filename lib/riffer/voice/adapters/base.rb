# frozen_string_literal: true
# rbs_inline: enabled

# Base class for internal voice provider adapters.
class Riffer::Voice::Adapters::Base
  # Provider-specific model identifier.
  attr_reader :model #: String

  #: (model: String, runtime_executor: (Riffer::Voice::Runtime::ManagedAsync | Riffer::Voice::Runtime::BackgroundAsync), ?logger: untyped) -> void
  def initialize(model:, runtime_executor:, logger: nil)
    @model = model
    @runtime_executor = runtime_executor
    @logger = logger
  end

  #: (system_prompt: String, on_event: ^(Riffer::Voice::Events::Base) -> void, ?tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]], ?config: Hash[Symbol | String, untyped]) -> bool
  def connect(system_prompt:, on_event:, tools: [], config: {})
    raise NotImplementedError, "Subclasses must implement #connect"
  end

  #: () -> bool
  def connected?
    raise NotImplementedError, "Subclasses must implement #connected?"
  end

  #: (text: String) -> void
  def send_text_turn(text:)
    raise NotImplementedError, "Subclasses must implement #send_text_turn"
  end

  #: (payload: String, mime_type: String) -> void
  def send_audio_chunk(payload:, mime_type:)
    raise NotImplementedError, "Subclasses must implement #send_audio_chunk"
  end

  #: (call_id: String, result: untyped) -> void
  def send_tool_response(call_id:, result:)
    raise NotImplementedError, "Subclasses must implement #send_tool_response"
  end

  #: () -> void
  def close
    raise NotImplementedError, "Subclasses must implement #close"
  end

  private

  attr_reader :runtime_executor #: (Riffer::Voice::Runtime::ManagedAsync | Riffer::Voice::Runtime::BackgroundAsync)
  attr_reader :logger #: untyped

  #: () -> ^() -> untyped
  def driver_task_resolver
    -> { driver_task }
  end

  #: () -> ^(url: String, headers: Hash[String, String]) -> untyped
  def runtime_transport_factory
    if runtime_executor.respond_to?(:kind) && runtime_executor.kind == :background
      ->(url:, headers:) { Riffer::Voice::Transports::ThreadWebsocket.connect(url: url, headers: headers) }
    else
      ->(url:, headers:) { Riffer::Voice::Transports::AsyncWebsocket.connect(url: url, headers: headers) }
    end
  end

  #: () -> untyped
  def driver_task
    if runtime_executor.respond_to?(:task)
      runtime_executor.task
    else
      RuntimeTask.new(runtime_executor: runtime_executor)
    end
  end

  # Async task compatibility shim backed by voice runtime scheduling.
  class RuntimeTask
    #: (runtime_executor: Riffer::Voice::Runtime::BackgroundAsync) -> void
    def initialize(runtime_executor:)
      @runtime_executor = runtime_executor
    end

    #: (?annotation: String?) { () -> untyped } -> untyped
    def async(annotation: nil, &block)
      raise Riffer::ArgumentError, "async requires a block" unless block

      @runtime_executor.schedule(&block)
    end
  end
end
