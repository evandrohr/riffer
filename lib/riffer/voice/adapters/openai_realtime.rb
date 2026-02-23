# frozen_string_literal: true
# rbs_inline: enabled

# Internal adapter for OpenAI realtime voice provider.
class Riffer::Voice::Adapters::OpenAIRealtime < Riffer::Voice::Adapters::Base
  #: (model: String, runtime_executor: (Riffer::Voice::Runtime::ManagedAsync | Riffer::Voice::Runtime::BackgroundAsync), ?driver_factory: ^(model: String, task_resolver: ^() -> untyped, logger: untyped) -> untyped, ?logger: untyped) -> void
  def initialize(model:, runtime_executor:, driver_factory: nil, logger: nil)
    super(model: model, runtime_executor: runtime_executor, logger: logger)
    @driver_factory = driver_factory || method(:build_driver).to_proc
    @driver = @driver_factory.call(model: model, task_resolver: driver_task_resolver, logger: logger)
  end

  #: (system_prompt: String, on_event: ^(Riffer::Voice::Events::Base) -> void, ?tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]], ?config: Hash[Symbol | String, untyped]) -> bool
  def connect(system_prompt:, on_event:, tools: [], config: {})
    @driver.connect(
      system_prompt: system_prompt,
      tools: tools,
      config: config,
      callbacks: {on_event: on_event}
    )
  end

  #: (text: String) -> void
  def send_text_turn(text:)
    @driver.send_text_turn(text: text)
  end

  #: (payload: String, mime_type: String) -> void
  def send_audio_chunk(payload:, mime_type:)
    @driver.send_audio_chunk(payload: payload, mime_type: mime_type)
  end

  #: (call_id: String, result: untyped) -> void
  def send_tool_response(call_id:, result:)
    @driver.send_tool_response(call_id: call_id, result: result)
  end

  #: () -> void
  def close
    @driver.close
  end

  private

  #: (model: String, task_resolver: ^() -> untyped, logger: untyped) -> Riffer::Voice::Drivers::OpenAIRealtime
  def build_driver(model:, task_resolver:, logger:)
    Riffer::Voice::Drivers::OpenAIRealtime.new(model: model, task_resolver: task_resolver, logger: logger)
  end
end
