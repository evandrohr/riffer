# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Agent::Callbacks
  # Registers a callback for all durability checkpoint emissions.
  #
  #: () { (Hash[Symbol, untyped]) -> void } -> self
  def on_checkpoint(&block)
    register_checkpoint_callback(:on_checkpoint, &block)
  end

  # Registers a callback for turn-complete checkpoints.
  #
  #: () { (Hash[Symbol, untyped]) -> void } -> self
  def on_turn_complete_checkpoint(&block)
    register_checkpoint_callback(:on_turn_complete_checkpoint, &block)
  end

  # Registers a callback for tool-request checkpoints.
  #
  #: () { (Hash[Symbol, untyped]) -> void } -> self
  def on_tool_request_checkpoint(&block)
    register_checkpoint_callback(:on_tool_request_checkpoint, &block)
  end

  # Registers a callback for tool-response checkpoints.
  #
  #: () { (Hash[Symbol, untyped]) -> void } -> self
  def on_tool_response_checkpoint(&block)
    register_checkpoint_callback(:on_tool_response_checkpoint, &block)
  end

  # Registers a callback for recoverable-error checkpoints.
  #
  #: () { (Hash[Symbol, untyped]) -> void } -> self
  def on_recoverable_error_checkpoint(&block)
    register_checkpoint_callback(:on_recoverable_error_checkpoint, &block)
  end

  # Registers a callback invoked for every consumed voice event.
  #
  #: () { (Riffer::Voice::Events::Base) -> void } -> self
  def on_event(&block)
    register_event_callback(:on_event, &block)
  end

  # Registers a callback invoked for audio chunk events.
  #
  #: () { (Riffer::Voice::Events::AudioChunk) -> void } -> self
  def on_audio_chunk(&block)
    register_event_callback(:on_audio_chunk, &block)
  end

  # Registers a callback invoked for input transcript events.
  #
  #: () { (Riffer::Voice::Events::InputTranscript) -> void } -> self
  def on_input_transcript(&block)
    register_event_callback(:on_input_transcript, &block)
  end

  # Registers a callback invoked for output transcript events.
  #
  #: () { (Riffer::Voice::Events::OutputTranscript) -> void } -> self
  def on_output_transcript(&block)
    register_event_callback(:on_output_transcript, &block)
  end

  # Registers a callback invoked for tool-call events.
  #
  #: () { (Riffer::Voice::Events::ToolCall) -> void } -> self
  def on_tool_call(&block)
    register_event_callback(:on_tool_call, &block)
  end

  # Registers a callback invoked for interruption events.
  #
  #: () { (Riffer::Voice::Events::Interrupt) -> void } -> self
  def on_interrupt(&block)
    register_event_callback(:on_interrupt, &block)
  end

  # Registers a callback invoked for turn-complete events.
  #
  #: () { (Riffer::Voice::Events::TurnComplete) -> void } -> self
  def on_turn_complete(&block)
    register_event_callback(:on_turn_complete, &block)
  end

  # Registers a callback invoked for usage events.
  #
  #: () { (Riffer::Voice::Events::Usage) -> void } -> self
  def on_usage(&block)
    register_event_callback(:on_usage, &block)
  end

  # Registers a callback invoked for error events.
  #
  #: () { (Riffer::Voice::Events::Error) -> void } -> self
  def on_error(&block)
    register_event_callback(:on_error, &block)
  end

  private

  #: (Symbol) { (Riffer::Voice::Events::Base) -> void } -> self
  def register_event_callback(callback_key, &block)
    raise Riffer::ArgumentError, "#{callback_key} requires a block" unless block_given?

    @event_callbacks.fetch(callback_key) << block
    self
  end

  #: (Symbol) { (Hash[Symbol, untyped]) -> void } -> self
  def register_checkpoint_callback(callback_key, &block)
    raise Riffer::ArgumentError, "#{callback_key} requires a block" unless block_given?

    @checkpoint_callbacks.fetch(callback_key) << block
    self
  end

  #: (Symbol, Hash[Symbol, untyped]) -> void
  def emit_checkpoint(checkpoint_type, payload)
    checkpoint = checkpoint_payload(checkpoint_type, payload)
    safely_invoke_checkpoint_callbacks(:on_checkpoint, checkpoint)
    callback_key = checkpoint_callback_key_for(checkpoint_type)
    safely_invoke_checkpoint_callbacks(callback_key, checkpoint)
  end

  #: (Symbol, Hash[Symbol, untyped]) -> Hash[Symbol, untyped]
  def checkpoint_payload(checkpoint_type, payload)
    {
      type: checkpoint_type,
      at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
      active_profile: @active_profile,
      action_budget_state: action_budget_state
    }.merge(payload)
  end

  #: (Symbol, Hash[Symbol, untyped]) -> void
  def safely_invoke_checkpoint_callbacks(callback_key, payload)
    @checkpoint_callbacks.fetch(callback_key).each do |callback|
      callback.call(payload)
    end
  rescue => error
    raise Riffer::Error, "#{callback_key} callback failed for checkpoint #{payload[:type]}: #{error.class}: #{error.message}"
  end

  #: (Symbol) -> Symbol
  def checkpoint_callback_key_for(checkpoint_type)
    case checkpoint_type
    when :turn_complete
      :on_turn_complete_checkpoint
    when :tool_request
      :on_tool_request_checkpoint
    when :tool_response
      :on_tool_response_checkpoint
    when :recoverable_error
      :on_recoverable_error_checkpoint
    else
      :on_checkpoint
    end
  end

  #: (Riffer::Voice::Events::Base) -> void
  def dispatch_event_callbacks(event)
    safely_invoke_callbacks(:on_event, event)
    callback_key = callback_key_for(event)
    safely_invoke_callbacks(callback_key, event) if callback_key
  end

  #: (Symbol, Riffer::Voice::Events::Base) -> void
  def safely_invoke_callbacks(callback_key, event)
    @event_callbacks.fetch(callback_key).each do |callback|
      callback.call(event)
    end
  rescue => error
    raise Riffer::Error,
      "#{callback_key} callback failed for #{event.class.name}: #{error.class}: #{error.message}"
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

  #: () -> Hash[Symbol, Array[^(Riffer::Voice::Events::Base) -> void]]
  def default_event_callbacks
    Riffer::Voice::Agent::CALLBACK_KEYS.each_with_object({}) do |callback_key, callbacks|
      callbacks[callback_key] = []
    end
  end

  #: () -> Hash[Symbol, Array[^(Hash[Symbol, untyped]) -> void]]
  def default_checkpoint_callbacks
    Riffer::Voice::Agent::CHECKPOINT_KEYS.each_with_object({}) do |callback_key, callbacks|
      callbacks[callback_key] = []
    end
  end
end
