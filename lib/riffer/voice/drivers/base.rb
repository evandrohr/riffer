# frozen_string_literal: true
# rbs_inline: enabled

# Base class for realtime voice drivers.
class Riffer::Voice::Drivers::Base
  include Riffer::Helpers::Dependencies

  # Provider model identifier.
  attr_reader :model #: String?

  #: (?model: String?, ?logger: untyped) -> void
  def initialize(model: nil, logger: nil)
    @model = model
    @logger = logger
    @connected = false
    @closed = false
    reset_callbacks({})
  end

  #: (system_prompt: String, ?tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]], ?config: Hash[Symbol | String, untyped], ?callbacks: Hash[Symbol, ^(Riffer::Voice::Events::Base) -> void]) -> bool
  def connect(system_prompt:, tools: [], config: {}, callbacks: {})
    raise NotImplementedError, "Subclasses must implement #connect"
  end

  #: () -> bool
  def connected?
    @connected == true
  end

  #: (payload: String, mime_type: String) -> void
  def send_audio_chunk(payload:, mime_type:)
    raise NotImplementedError, "Subclasses must implement #send_audio_chunk"
  end

  #: (text: String, ?role: String) -> void
  def send_text_turn(text:, role: "user")
    raise NotImplementedError, "Subclasses must implement #send_text_turn"
  end

  #: (call_id: String, result: untyped) -> void
  def send_tool_response(call_id:, result:)
    raise NotImplementedError, "Subclasses must implement #send_tool_response"
  end

  #: (?reason: String?) -> void
  def close(reason: nil)
    raise NotImplementedError, "Subclasses must implement #close"
  end

  private

  #: (Hash[Symbol, untyped]) -> void
  def reset_callbacks(callbacks)
    defaults = {
      on_event: ->(_event) {},
      on_audio_chunk: ->(_event) {},
      on_input_transcript: ->(_event) {},
      on_output_transcript: ->(_event) {},
      on_tool_call: ->(_event) {},
      on_interrupt: ->(_event) {},
      on_turn_complete: ->(_event) {},
      on_usage: ->(_event) {},
      on_error: ->(_event) {}
    }

    @callbacks = defaults.merge((callbacks || {}).transform_keys(&:to_sym))
  end

  #: (Riffer::Voice::Events::Base) -> Riffer::Voice::Events::Base
  def emit_event(event)
    return event if @closed

    safely_invoke(:on_event, event)
    callback_key = callback_key_for(event)
    safely_invoke(callback_key, event) if callback_key
    event
  end

  #: (code: String, message: String, ?retriable: bool, ?metadata: Hash[Symbol, untyped]) -> Riffer::Voice::Events::Error
  def emit_error(code:, message:, retriable: false, metadata: {})
    event = Riffer::Voice::Events::Error.new(
      code: code,
      message: message,
      retriable: retriable,
      metadata: metadata
    )

    return event if @closed

    safely_invoke(:on_event, event, emit_callback_error: false)
    safely_invoke(:on_error, event, emit_callback_error: false)
    event
  end

  #: (Symbol, Riffer::Voice::Events::Base, ?emit_callback_error: bool) -> void
  def safely_invoke(callback_key, event, emit_callback_error: true)
    @callbacks.fetch(callback_key).call(event)
  rescue => error
    return unless emit_callback_error

    emit_error(
      code: "callback_error",
      message: "#{callback_key} callback failed: #{error.message}",
      retriable: false,
      metadata: {
        callback: callback_key,
        event_class: event.class.name,
        error_class: error.class.name
      }
    )
  end

  #: (Riffer::Voice::Events::Base) -> Symbol?
  def callback_key_for(event)
    case event
    when Riffer::Voice::Events::AudioChunk
      :on_audio_chunk
    when Riffer::Voice::Events::InputTranscript
      :on_input_transcript
    when Riffer::Voice::Events::OutputTranscript
      :on_output_transcript
    when Riffer::Voice::Events::ToolCall
      :on_tool_call
    when Riffer::Voice::Events::Interrupt
      :on_interrupt
    when Riffer::Voice::Events::TurnComplete
      :on_turn_complete
    when Riffer::Voice::Events::Usage
      :on_usage
    when Riffer::Voice::Events::Error
      :on_error
    end
  end

  #: () -> void
  def mark_connected!
    @connected = true
    @closed = false
  end

  #: () -> void
  def mark_disconnected!
    @connected = false
  end

  #: () -> bool
  def closed?
    @closed == true
  end

  #: () -> void
  def mark_closed!
    @closed = true
    @connected = false
  end

  #: (untyped) -> untyped
  def ensure_async_task!(task)
    return task if task

    raise Riffer::ArgumentError, "Realtime voice drivers require an Async task context. Wrap usage with Async do ... end."
  end

  #: (Hash[Symbol | String, untyped]) -> Hash[String, untyped]
  def stringify_hash(hash)
    hash.each_with_object({}) do |(key, value), result|
      result[key.to_s] = value
    end
  end

  #: (singleton(Riffer::Tool)) -> Hash[Symbol, untyped]
  def tool_to_json_schema(tool)
    {
      type: "function",
      name: tool.name,
      description: tool.description,
      parameters: tool.parameters_schema,
      strict: true
    }
  end

  #: (untyped) -> void
  def log_debug(_payload)
    nil
  end
end
