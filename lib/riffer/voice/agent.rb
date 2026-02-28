# frozen_string_literal: true
# rbs_inline: enabled

# High-level orchestration wrapper for realtime voice sessions.
#
# Riffer::Voice::Agent keeps Riffer::Voice::Session as a low-level transport API
# and adds optional automatic tool-call execution using Riffer::Tool classes.
#
#   class SupportVoiceAgent < Riffer::Voice::Agent
#     model "openai/gpt-realtime-1.5"
#     instructions "You are a concise support assistant."
#     uses_tools [LookupAccountTool]
#   end
#
#   agent = SupportVoiceAgent.connect(runtime: :auto)
#   agent.send_text_turn(text: "Hello")
#   agent.events.each do |event|
#     puts event.class.name
#   end
#
class Riffer::Voice::Agent
  extend Riffer::Helpers::Validations

  # Connected voice session.
  attr_reader :session #: Riffer::Voice::Session?

  # Tool execution context passed to Riffer::Tool#call.
  attr_accessor :tool_context #: Hash[Symbol, untyped]?

  CALLBACK_KEYS = [
    :on_event,
    :on_audio_chunk,
    :on_input_transcript,
    :on_output_transcript,
    :on_tool_call,
    :on_interrupt,
    :on_turn_complete,
    :on_usage,
    :on_error
  ].freeze

  #: (?(String | Proc)?) -> (String | Proc)?
  def self.model(model_string_or_proc = nil)
    return @model if model_string_or_proc.nil?

    if model_string_or_proc.is_a?(Proc)
      @model = model_string_or_proc
    else
      validate_is_string!(model_string_or_proc, "model")
      @model = model_string_or_proc
    end
  end

  #: (?String?) -> String?
  def self.instructions(instructions_text = nil)
    return @instructions if instructions_text.nil?
    validate_is_string!(instructions_text, "instructions")
    @instructions = instructions_text
  end

  #: (?(Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]] | Proc)?) -> (Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]] | Proc)?
  def self.uses_tools(tools_or_lambda = nil)
    return @tools_config if tools_or_lambda.nil?
    @tools_config = tools_or_lambda
  end

  # Gets or sets the default runtime mode used by #connect.
  #
  #: (?Symbol?) -> Symbol?
  def self.runtime(mode = nil)
    return @runtime if mode.nil?

    unless Riffer::Voice::SUPPORTED_RUNTIMES.include?(mode)
      raise Riffer::ArgumentError, "runtime must be one of: #{Riffer::Voice::SUPPORTED_RUNTIMES.join(", ")}"
    end

    @runtime = mode
  end

  # Gets or sets default connect config merged into #connect(config: ...).
  #
  #: (?Hash[Symbol | String, untyped]?) -> Hash[Symbol | String, untyped]
  def self.voice_config(config = nil)
    return deep_copy(@voice_config || {}) if config.nil?
    raise Riffer::ArgumentError, "voice_config must be a Hash" unless config.is_a?(Hash)

    @voice_config = deep_copy(config)
  end

  # Gets or sets default automatic voice tool-call handling behavior.
  #
  #: (?bool?) -> bool
  def self.auto_handle_tool_calls(value = nil)
    if value.nil?
      return true if @auto_handle_tool_calls.nil?

      return @auto_handle_tool_calls
    end

    raise Riffer::ArgumentError, "auto_handle_tool_calls must be true or false" unless value == true || value == false

    @auto_handle_tool_calls = value
  end

  #: (**untyped) -> Riffer::Voice::Agent
  def self.connect(**kwargs)
    tool_context = kwargs.delete(:tool_context)
    auto_handle_tool_calls = kwargs.delete(:auto_handle_tool_calls)
    init_options = {tool_context: tool_context}
    init_options[:auto_handle_tool_calls] = auto_handle_tool_calls unless auto_handle_tool_calls.nil?
    agent = new(**init_options)
    agent.connect(**kwargs)
    agent
  end

  #: (?tool_context: Hash[Symbol, untyped]?, ?auto_handle_tool_calls: bool?) -> void
  def initialize(tool_context: nil, auto_handle_tool_calls: nil)
    raise Riffer::ArgumentError, "tool_context must be a Hash or nil" unless tool_context.nil? || tool_context.is_a?(Hash)
    invalid_auto_tool_calls = !auto_handle_tool_calls.nil? && auto_handle_tool_calls != true && auto_handle_tool_calls != false
    raise Riffer::ArgumentError, "auto_handle_tool_calls must be true, false, or nil" if invalid_auto_tool_calls

    @tool_context = tool_context
    @auto_handle_tool_calls = auto_handle_tool_calls.nil? ? self.class.auto_handle_tool_calls : auto_handle_tool_calls
    @model_config = self.class.model
    @instructions_text = self.class.instructions
    @tools_config = self.class.uses_tools
    @runtime_config = self.class.runtime
    @voice_config = self.class.voice_config
    @connected_tools = [] #: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]
    @event_callbacks = default_event_callbacks #: Hash[Symbol, Array[^(Riffer::Voice::Events::Base) -> void]]
    @session = nil
  end

  #: (?model: String?, ?system_prompt: String?, ?tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]?, ?config: Hash[Symbol | String, untyped]?, ?runtime: Symbol?, ?adapter_factory: ^(adapter_identifier: Symbol, model: String, runtime_executor: (Riffer::Voice::Runtime::ManagedAsync | Riffer::Voice::Runtime::BackgroundAsync)) -> untyped) -> self
  def connect(model: nil, system_prompt: nil, tools: nil, config: nil, runtime: nil, adapter_factory: nil)
    close if @session && !@session.closed?

    resolved_model = resolve_model(model)
    resolved_system_prompt = resolve_system_prompt(system_prompt)
    resolved_tools = resolve_tools(tools)
    resolved_config = resolve_config(config)
    resolved_runtime = resolve_runtime(runtime)

    @session = Riffer::Voice.connect(
      model: resolved_model,
      system_prompt: resolved_system_prompt,
      tools: resolved_tools,
      config: resolved_config,
      runtime: resolved_runtime,
      adapter_factory: adapter_factory
    )
    @connected_tools = resolved_tools
    self
  end

  #: () -> bool
  def connected?
    @session&.connected? == true
  end

  #: () -> bool
  def closed?
    @session.nil? || @session.closed?
  end

  #: () -> Symbol
  def runtime_kind
    current_session.runtime_kind
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

  #: (text: String) -> bool
  def send_text_turn(text:)
    current_session.send_text_turn(text: text)
  end

  #: (payload: String, mime_type: String) -> bool
  def send_audio_chunk(payload:, mime_type:)
    current_session.send_audio_chunk(payload: payload, mime_type: mime_type)
  end

  #: (call_id: String, result: untyped) -> bool
  def send_tool_response(call_id:, result:)
    current_session.send_tool_response(call_id: call_id, result: result)
  end

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

  #: () -> void
  def close
    return if @session.nil?

    @session.close
  end

  private

  #: () -> Riffer::Voice::Session
  def current_session
    session = @session
    raise Riffer::Error, "Voice agent is not connected" if session.nil?

    session
  end

  #: (Riffer::Voice::Events::Base, auto_handle_tool_calls: bool) -> Riffer::Voice::Events::Base
  def consume_event(event, auto_handle_tool_calls:)
    handle_tool_call_event(event) if auto_handle_tool_calls
    dispatch_event_callbacks(event)
    event
  end

  #: (Riffer::Voice::Events::Base) -> void
  def handle_tool_call_event(event)
    return unless event.is_a?(Riffer::Voice::Events::ToolCall)

    result = execute_tool_call(event)
    current_session.send_tool_response(call_id: event.call_id, result: serialize_tool_result(result))
  end

  #: (Symbol) { (Riffer::Voice::Events::Base) -> void } -> self
  def register_event_callback(callback_key, &block)
    raise Riffer::ArgumentError, "#{callback_key} requires a block" unless block_given?

    @event_callbacks.fetch(callback_key) << block
    self
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

  #: (Riffer::Voice::Events::ToolCall) -> Riffer::Tools::Response
  def execute_tool_call(tool_call_event)
    tool_class = find_tool_class(tool_call_event.name)

    if tool_class.nil?
      return Riffer::Tools::Response.error(
        "Unknown tool '#{tool_call_event.name}'",
        type: :unknown_tool
      )
    end

    tool_instance = tool_class.new
    arguments = parse_tool_arguments(tool_call_event.arguments_hash)

    begin
      tool_instance.call_with_validation(context: @tool_context, **arguments)
    rescue Riffer::TimeoutError => e
      Riffer::Tools::Response.error(e.message, type: :timeout_error)
    rescue Riffer::ValidationError => e
      Riffer::Tools::Response.error(e.message, type: :validation_error)
    rescue => e
      Riffer::Tools::Response.error("Error executing tool: #{e.message}", type: :execution_error)
    end
  end

  #: (Riffer::Tools::Response) -> (String | Hash[String, untyped])
  def serialize_tool_result(result)
    return result.content unless result.error?

    {
      "content" => result.content,
      "error" => {
        "type" => result.error_type.to_s,
        "message" => result.error_message
      }
    }
  end

  #: (String) -> singleton(Riffer::Tool)?
  def find_tool_class(name)
    @connected_tools.find do |tool|
      tool.is_a?(Class) && tool <= Riffer::Tool && tool.name == name
    end
  end

  #: (Hash[String, untyped]) -> Hash[Symbol, untyped]
  def parse_tool_arguments(arguments)
    return {} if arguments.empty?

    arguments.each_with_object({}) do |(key, value), result|
      result[key.to_sym] = value
    end
  end

  #: (String?) -> String
  def resolve_model(model_override)
    return validate_resolved_model!(model_override) unless model_override.nil?

    config = @model_config
    if config.is_a?(Proc)
      return validate_resolved_model!((config.arity == 0) ? config.call : config.call(@tool_context))
    end

    return validate_resolved_model!(config) if config

    raise Riffer::ArgumentError, "model must be provided or configured via .model"
  end

  #: (String?) -> String
  def resolve_system_prompt(system_prompt_override)
    return validate_resolved_system_prompt!(system_prompt_override) unless system_prompt_override.nil?
    return validate_resolved_system_prompt!(@instructions_text) unless @instructions_text.nil?

    raise Riffer::ArgumentError, "system_prompt must be provided or configured via .instructions"
  end

  #: (Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]?) -> Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]
  def resolve_tools(tools_override)
    return validate_resolved_tools!(tools_override) unless tools_override.nil?

    config = @tools_config
    return [] if config.nil?

    if config.is_a?(Proc)
      return validate_resolved_tools!((config.arity == 0) ? config.call : config.call(@tool_context))
    end

    validate_resolved_tools!(config)
  end

  #: (Hash[Symbol | String, untyped]?) -> Hash[Symbol | String, untyped]
  def resolve_config(config_override)
    return deep_copy(@voice_config) if config_override.nil?
    raise Riffer::ArgumentError, "config must be a Hash" unless config_override.is_a?(Hash)

    deep_merge(deep_copy(@voice_config), config_override)
  end

  #: (Symbol?) -> Symbol
  def resolve_runtime(runtime_override)
    runtime = runtime_override.nil? ? @runtime_config : runtime_override
    runtime = :auto if runtime.nil?
    unless Riffer::Voice::SUPPORTED_RUNTIMES.include?(runtime)
      raise Riffer::ArgumentError, "runtime must be one of: #{Riffer::Voice::SUPPORTED_RUNTIMES.join(", ")}"
    end

    runtime
  end

  #: (untyped) -> String
  def validate_resolved_model!(value)
    return value if value.is_a?(String) && !value.empty?

    raise Riffer::ArgumentError, "resolved model must be a non-empty String"
  end

  #: (untyped) -> String
  def validate_resolved_system_prompt!(value)
    return value if value.is_a?(String) && !value.empty?

    raise Riffer::ArgumentError, "resolved system_prompt must be a non-empty String"
  end

  #: (untyped) -> Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]
  def validate_resolved_tools!(value)
    return value if value.is_a?(Array)

    raise Riffer::ArgumentError, "resolved tools must be an Array"
  end

  #: (untyped) -> untyped
  def self.deep_copy(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested), result|
        result[key] = deep_copy(nested)
      end
    when Array
      value.map { |nested| deep_copy(nested) }
    else
      value
    end
  end
  private_class_method :deep_copy

  #: () -> Hash[Symbol, Array[^(Riffer::Voice::Events::Base) -> void]]
  def default_event_callbacks
    CALLBACK_KEYS.each_with_object({}) do |callback_key, callbacks|
      callbacks[callback_key] = []
    end
  end

  #: (untyped) -> untyped
  def deep_copy(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested), result|
        result[key] = deep_copy(nested)
      end
    when Array
      value.map { |nested| deep_copy(nested) }
    else
      value
    end
  end

  #: (Hash[Symbol | String, untyped], Hash[Symbol | String, untyped]) -> Hash[Symbol | String, untyped]
  def deep_merge(base, overrides)
    merged = deep_copy(base)

    overrides.each do |key, value|
      merged[key] = if merged[key].is_a?(Hash) && value.is_a?(Hash)
        deep_merge(merged[key], value)
      else
        deep_copy(value)
      end
    end

    merged
  end
end
