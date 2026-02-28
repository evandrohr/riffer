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

  # Gets or sets the default tool executor used by automatic ToolCall handling.
  #
  #: (?(^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped)?) -> ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped
  def self.tool_executor(executor = nil)
    return @tool_executor if executor.nil?
    raise Riffer::ArgumentError, "tool_executor must respond to #call" unless executor.respond_to?(:call)

    @tool_executor = executor
  end

  # Gets or sets action budget defaults enforced during automatic tool dispatch.
  #
  #: (**untyped) -> Hash[Symbol, Integer?]
  def self.action_budget(**kwargs)
    return deep_copy(@action_budget || {}) if kwargs.empty?

    @action_budget = validate_action_budget_config!(kwargs, "action_budget")
  end

  # Gets or sets the mutation classifier used by budget/policy checks.
  #
  #: (?(^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> bool)?) -> ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> bool
  def self.mutation_classifier(classifier = nil)
    return @mutation_classifier if classifier.nil?
    raise Riffer::ArgumentError, "mutation_classifier must respond to #call" unless classifier.respond_to?(:call)

    @mutation_classifier = classifier
  end

  # Gets or sets the dispatch policy hook used before automatic tool execution.
  #
  #: (?(^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped)?) -> ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped
  def self.tool_policy(policy = nil)
    return @tool_policy if policy.nil?
    raise Riffer::ArgumentError, "tool_policy must respond to #call" unless policy.respond_to?(:call)

    @tool_policy = policy
  end

  # Gets or sets the approval callback used for gated tool dispatch.
  #
  #: (?(^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent, decision: Hash[Symbol, untyped]) -> untyped)?) -> ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent, decision: Hash[Symbol, untyped]) -> untyped
  def self.approval_callback(callback = nil)
    return @approval_callback if callback.nil?
    raise Riffer::ArgumentError, "approval_callback must respond to #call" unless callback.respond_to?(:call)

    @approval_callback = callback
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

  # Defines or retrieves a named profile config bundle.
  #
  # When called with a block, the profile is defined/updated.
  # When called without a block, returns the stored profile hash or nil.
  #
  #: ((String | Symbol), ?{ () -> void }) -> Hash[Symbol, untyped]?
  def self.profile(name, &block)
    profile_name = normalize_profile_name!(name)

    if block_given?
      definition = ProfileDefinition.new
      definition.instance_exec(&block)
      profiles = @profiles || {}
      profiles[profile_name] = definition.to_h
      @profiles = profiles
      return deep_copy(@profiles[profile_name])
    end

    deep_copy((@profiles || {})[profile_name])
  end

  # Returns all named profile definitions.
  #
  #: () -> Hash[Symbol, Hash[Symbol, untyped]]
  def self.profiles
    deep_copy(@profiles || {})
  end

  #: (**untyped) -> Riffer::Voice::Agent
  def self.connect(**kwargs)
    tool_context = kwargs.delete(:tool_context)
    auto_handle_tool_calls = kwargs.delete(:auto_handle_tool_calls)
    tool_executor = kwargs.delete(:tool_executor)
    action_budget = kwargs.delete(:action_budget)
    mutation_classifier = kwargs.delete(:mutation_classifier)
    tool_policy = kwargs.delete(:tool_policy)
    approval_callback = kwargs.delete(:approval_callback)
    init_options = {tool_context: tool_context}
    init_options[:auto_handle_tool_calls] = auto_handle_tool_calls unless auto_handle_tool_calls.nil?
    init_options[:tool_executor] = tool_executor unless tool_executor.nil?
    init_options[:action_budget] = action_budget unless action_budget.nil?
    init_options[:mutation_classifier] = mutation_classifier unless mutation_classifier.nil?
    init_options[:tool_policy] = tool_policy unless tool_policy.nil?
    init_options[:approval_callback] = approval_callback unless approval_callback.nil?
    agent = new(**init_options)
    agent.connect(**kwargs)
    agent
  end

  #: (?tool_context: Hash[Symbol, untyped]?, ?auto_handle_tool_calls: bool?, ?tool_executor: ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped?, ?action_budget: Hash[Symbol | String, untyped]?, ?mutation_classifier: ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> bool?, ?tool_policy: ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped?, ?approval_callback: ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent, decision: Hash[Symbol, untyped]) -> untyped?) -> void
  def initialize(
    tool_context: nil,
    auto_handle_tool_calls: nil,
    tool_executor: nil,
    action_budget: nil,
    mutation_classifier: nil,
    tool_policy: nil,
    approval_callback: nil
  )
    raise Riffer::ArgumentError, "tool_context must be a Hash or nil" unless tool_context.nil? || tool_context.is_a?(Hash)
    invalid_auto_tool_calls = !auto_handle_tool_calls.nil? && auto_handle_tool_calls != true && auto_handle_tool_calls != false
    raise Riffer::ArgumentError, "auto_handle_tool_calls must be true, false, or nil" if invalid_auto_tool_calls
    validate_tool_executor!(tool_executor, "tool_executor") unless tool_executor.nil?
    validate_action_budget_config!(action_budget, "action_budget") unless action_budget.nil?
    validate_callable!(mutation_classifier, "mutation_classifier") unless mutation_classifier.nil?
    validate_callable!(tool_policy, "tool_policy") unless tool_policy.nil?
    validate_callable!(approval_callback, "approval_callback") unless approval_callback.nil?

    @tool_context = tool_context
    @auto_handle_tool_calls = auto_handle_tool_calls.nil? ? self.class.auto_handle_tool_calls : auto_handle_tool_calls
    @model_config = self.class.model
    @instructions_text = self.class.instructions
    @tools_config = self.class.uses_tools
    @tool_executor = tool_executor || self.class.tool_executor
    @action_budget = action_budget.nil? ? self.class.action_budget : validate_action_budget_config!(action_budget, "action_budget")
    @mutation_classifier = mutation_classifier || self.class.mutation_classifier
    @tool_policy = tool_policy || self.class.tool_policy
    @approval_callback = approval_callback || self.class.approval_callback
    @runtime_config = self.class.runtime
    @voice_config = self.class.voice_config
    @connected_tools = [] #: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]
    @event_callbacks = default_event_callbacks #: Hash[Symbol, Array[^(Riffer::Voice::Events::Base) -> void]]
    @before_tool_execution_hooks = [] #: Array[^(Hash[Symbol, untyped]) -> void]
    @after_tool_execution_hooks = [] #: Array[^(Hash[Symbol, untyped]) -> void]
    @tool_execution_error_hooks = [] #: Array[^(Hash[Symbol, untyped]) -> void]
    @tool_call_count = 0
    @mutation_tool_call_count = 0
    @session = nil
  end

  #: (?model: String?, ?system_prompt: String?, ?tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]?, ?config: Hash[Symbol | String, untyped]?, ?runtime: Symbol?, ?profile: (String | Symbol)?, ?tool_executor: ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped?, ?action_budget: Hash[Symbol | String, untyped]?, ?mutation_classifier: ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> bool?, ?tool_policy: ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped?, ?approval_callback: ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent, decision: Hash[Symbol, untyped]) -> untyped?, ?adapter_factory: ^(adapter_identifier: Symbol, model: String, runtime_executor: (Riffer::Voice::Runtime::ManagedAsync | Riffer::Voice::Runtime::BackgroundAsync)) -> untyped) -> self
  def connect(
    model: nil,
    system_prompt: nil,
    tools: nil,
    config: nil,
    runtime: nil,
    profile: nil,
    tool_executor: nil,
    action_budget: nil,
    mutation_classifier: nil,
    tool_policy: nil,
    approval_callback: nil,
    adapter_factory: nil
  )
    close if @session && !@session.closed?
    profile_config = resolve_profile(profile)

    unless tool_executor.nil?
      validate_tool_executor!(tool_executor, "tool_executor")
      @tool_executor = tool_executor
    end
    if tool_executor.nil? && profile_config.key?(:tool_executor)
      validate_tool_executor!(profile_config[:tool_executor], "profile tool_executor")
      @tool_executor = profile_config[:tool_executor]
    end
    @action_budget = resolve_action_budget(action_budget, profile_config)
    @mutation_classifier = resolve_mutation_classifier(mutation_classifier, profile_config)
    @tool_policy = resolve_tool_policy(tool_policy, profile_config)
    @approval_callback = resolve_approval_callback(approval_callback, profile_config)
    validate_callable!(@mutation_classifier, "mutation_classifier") unless @mutation_classifier.nil?
    validate_callable!(@tool_policy, "tool_policy") unless @tool_policy.nil?
    validate_callable!(@approval_callback, "approval_callback") unless @approval_callback.nil?
    @tool_call_count = 0
    @mutation_tool_call_count = 0

    resolved_model = resolve_model(model, profile_config)
    resolved_system_prompt = resolve_system_prompt(system_prompt, profile_config)
    resolved_tools = resolve_tools(tools, profile_config)
    resolved_config = resolve_config(config, profile_config)
    resolved_runtime = resolve_runtime(runtime, profile_config)

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

  # Returns current action budget limits and counters for this connection.
  #
  #: () -> Hash[Symbol, Integer?]
  def action_budget_state
    {
      max_tool_calls: @action_budget[:max_tool_calls],
      max_mutation_calls: @action_budget[:max_mutation_calls],
      tool_calls: @tool_call_count,
      mutation_tool_calls: @mutation_tool_call_count
    }
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

  # Registers a callback executed before each automatic tool execution.
  #
  #: () { (Hash[Symbol, untyped]) -> void } -> self
  def on_before_tool_execution(&block)
    register_tool_hook(:before, &block)
  end

  # Registers a callback executed after each automatic tool execution.
  #
  #: () { (Hash[Symbol, untyped]) -> void } -> self
  def on_after_tool_execution(&block)
    register_tool_hook(:after, &block)
  end

  # Registers a callback executed for automatic tool execution errors.
  #
  #: () { (Hash[Symbol, untyped]) -> void } -> self
  def on_tool_execution_error(&block)
    register_tool_hook(:error, &block)
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
    invalid_timeout = !timeout.nil? && (!timeout.is_a?(Numeric) || timeout < 0)
    raise Riffer::ArgumentError, "timeout must be nil or >= 0" if invalid_timeout
    return enum_for(:run_loop, timeout: timeout, auto_handle_tool_calls: auto_handle_tool_calls) unless block_given?

    deadline = timeout.nil? ? nil : monotonic_time + timeout

    loop do
      break if closed? || !connected?

      next_timeout = remaining_timeout(deadline)
      break if !deadline.nil? && next_timeout <= 0

      event = next_event(timeout: next_timeout, auto_handle_tool_calls: auto_handle_tool_calls)
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
    invalid_timeout = !timeout.nil? && (!timeout.is_a?(Numeric) || timeout < 0)
    raise Riffer::ArgumentError, "timeout must be nil or >= 0" if invalid_timeout

    send_text_turn(text: text) unless text.nil?

    collected = []
    deadline = timeout.nil? ? nil : monotonic_time + timeout

    loop do
      break if closed? || !connected?

      next_timeout = remaining_timeout(deadline)
      break if !deadline.nil? && next_timeout <= 0

      event = next_event(timeout: next_timeout, auto_handle_tool_calls: auto_handle_tool_calls)
      break if event.nil?

      collected << event
      break if event.is_a?(Riffer::Voice::Events::TurnComplete) || event.is_a?(Riffer::Voice::Events::Interrupt)
    end

    collected
  end

  # Drains currently available events without blocking.
  #
  #: (?max_events: Integer?, ?auto_handle_tool_calls: bool) -> Array[Riffer::Voice::Events::Base]
  def drain_available_events(max_events: nil, auto_handle_tool_calls: @auto_handle_tool_calls)
    invalid_max_events = !max_events.nil? && (!max_events.is_a?(Integer) || max_events <= 0)
    raise Riffer::ArgumentError, "max_events must be nil or an Integer > 0" if invalid_max_events

    drained = []
    loop do
      break if !max_events.nil? && drained.length >= max_events

      event = next_event(timeout: 0, auto_handle_tool_calls: auto_handle_tool_calls)
      break if event.nil?

      drained << event
    end

    drained
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

  #: () -> Float
  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  #: (Float?) -> Numeric?
  def remaining_timeout(deadline)
    return nil if deadline.nil?

    remaining = deadline - monotonic_time
    remaining.negative? ? 0 : remaining
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
    schema_tool = find_schema_tool(tool_call_event.name)
    arguments = parse_tool_arguments(tool_call_event.arguments_hash)
    hook_payload = {
      call_id: tool_call_event.call_id,
      tool_name: tool_call_event.name,
      tool_class: tool_class,
      schema_tool: schema_tool,
      arguments: arguments,
      context: @tool_context,
      event: tool_call_event
    }

    begin
      policy_error = evaluate_dispatch_policy(hook_payload)
      if policy_error
        invoke_tool_hooks(@after_tool_execution_hooks, hook_payload.merge(result: policy_error))
        invoke_tool_hooks(@tool_execution_error_hooks, hook_payload.merge(result: policy_error))
        return policy_error
      end

      invoke_tool_hooks(@before_tool_execution_hooks, hook_payload)
      result = execute_tool_call_with_strategy(
        tool_call_event: tool_call_event,
        tool_class: tool_class,
        schema_tool: schema_tool,
        arguments: arguments
      )
      invoke_tool_hooks(@after_tool_execution_hooks, hook_payload.merge(result: result))
      invoke_tool_hooks(@tool_execution_error_hooks, hook_payload.merge(result: result)) if result.error?
      result
    rescue Riffer::TimeoutError => e
      result = Riffer::Tools::Response.error(e.message, type: :timeout_error)
      safely_invoke_tool_error_hooks(hook_payload, result, e)
      result
    rescue Riffer::ValidationError => e
      result = Riffer::Tools::Response.error(e.message, type: :validation_error)
      safely_invoke_tool_error_hooks(hook_payload, result, e)
      result
    rescue => e
      result = Riffer::Tools::Response.error("Error executing tool: #{e.message}", type: :execution_error)
      safely_invoke_tool_error_hooks(hook_payload, result, e)
      result
    end
  end

  #: (Hash[Symbol, untyped]) -> Riffer::Tools::Response?
  def evaluate_dispatch_policy(hook_payload)
    mutation_call = mutation_tool_call?(hook_payload)
    hook_payload[:mutation_call] = mutation_call

    budget_error = action_budget_error(mutation_call: mutation_call)
    return budget_error if budget_error

    decision = evaluate_tool_policy_decision(hook_payload)
    return policy_error_response(type: :policy_error, message: decision[:message]) if decision[:action] == :error

    decision = resolve_approval_decision(decision, hook_payload)
    if decision[:action] == :allow
      register_tool_dispatch(mutation_call: mutation_call)
      return nil
    end

    policy_error_response(type: decision[:type], message: decision[:message])
  end

  #: (Hash[Symbol, untyped]) -> bool
  def mutation_tool_call?(hook_payload)
    return false if @mutation_classifier.nil?

    result = @mutation_classifier.call(
      tool_call_event: hook_payload[:event],
      tool_class: hook_payload[:tool_class],
      schema_tool: hook_payload[:schema_tool],
      arguments: hook_payload[:arguments],
      context: @tool_context,
      agent: self
    )
    result == true
  rescue => error
    raise Riffer::Error,
      "mutation_classifier failed for #{hook_payload[:tool_name]}: #{error.class}: #{error.message}"
  end

  #: (mutation_call: bool) -> Riffer::Tools::Response?
  def action_budget_error(mutation_call:)
    max_tool_calls = @action_budget[:max_tool_calls]
    if max_tool_calls && @tool_call_count >= max_tool_calls
      return policy_error_response(
        type: :tool_call_budget_exceeded,
        message: "Tool call budget exceeded (max_tool_calls=#{max_tool_calls})"
      )
    end

    max_mutation_calls = @action_budget[:max_mutation_calls]
    if mutation_call && max_mutation_calls && @mutation_tool_call_count >= max_mutation_calls
      return policy_error_response(
        type: :mutation_budget_exceeded,
        message: "Mutation tool call budget exceeded (max_mutation_calls=#{max_mutation_calls})"
      )
    end

    nil
  end

  #: (mutation_call: bool) -> void
  def register_tool_dispatch(mutation_call:)
    @tool_call_count += 1
    @mutation_tool_call_count += 1 if mutation_call
  end

  #: (Hash[Symbol, untyped]) -> Hash[Symbol, untyped]
  def evaluate_tool_policy_decision(hook_payload)
    return {action: :allow} if @tool_policy.nil?

    raw_decision = @tool_policy.call(
      tool_call_event: hook_payload[:event],
      tool_name: hook_payload[:tool_name],
      tool_class: hook_payload[:tool_class],
      schema_tool: hook_payload[:schema_tool],
      arguments: hook_payload[:arguments],
      mutation_call: hook_payload[:mutation_call],
      context: @tool_context,
      agent: self
    )
    normalize_policy_decision(raw_decision)
  rescue => error
    {
      action: :error,
      type: :policy_error,
      message: "tool_policy failed for #{hook_payload[:tool_name]}: #{error.class}: #{error.message}"
    }
  end

  #: (Hash[Symbol, untyped], Hash[Symbol, untyped]) -> Hash[Symbol, untyped]
  def resolve_approval_decision(decision, hook_payload)
    return decision unless decision[:action] == :require_approval
    return {action: :deny, type: :approval_required, message: decision[:message]} if @approval_callback.nil?

    raw_decision = @approval_callback.call(
      tool_call_event: hook_payload[:event],
      tool_name: hook_payload[:tool_name],
      tool_class: hook_payload[:tool_class],
      schema_tool: hook_payload[:schema_tool],
      arguments: hook_payload[:arguments],
      mutation_call: hook_payload[:mutation_call],
      context: @tool_context,
      agent: self,
      decision: decision
    )
    normalize_approval_decision(raw_decision, hook_payload[:tool_name])
  rescue => error
    {
      action: :deny,
      type: :approval_error,
      message: "approval_callback failed for #{hook_payload[:tool_name]}: #{error.class}: #{error.message}"
    }
  end

  #: (untyped) -> Hash[Symbol, untyped]
  def normalize_policy_decision(raw_decision)
    case raw_decision
    when nil, true, :allow
      {action: :allow}
    when false, :deny
      {action: :deny, type: :policy_denied, message: "Tool dispatch denied by policy"}
    when :require_approval
      {action: :require_approval, type: :approval_required, message: "Tool dispatch requires approval"}
    when Hash
      normalize_hash_policy_decision(raw_decision)
    else
      {
        action: :deny,
        type: :policy_error,
        message: "tool_policy returned unsupported decision: #{raw_decision.inspect}"
      }
    end
  end

  #: (Hash[Symbol | String, untyped]) -> Hash[Symbol, untyped]
  def normalize_hash_policy_decision(raw_decision)
    action_value = hash_value(raw_decision, :action)
    action = case action_value
    when :allow, "allow"
      :allow
    when :deny, "deny"
      :deny
    when :require_approval, "require_approval"
      :require_approval
    else
      :deny
    end

    type = hash_value(raw_decision, :type) || default_policy_type_for(action)
    message = hash_value(raw_decision, :message) || default_policy_message_for(action)
    {action: action, type: type.to_sym, message: message.to_s}
  end

  #: (untyped, String) -> Hash[Symbol, untyped]
  def normalize_approval_decision(raw_decision, tool_name)
    case raw_decision
    when true, :allow
      {action: :allow}
    when false, nil, :deny
      {action: :deny, type: :approval_denied, message: "Approval denied for tool '#{tool_name}'"}
    when Hash
      approved = hash_value(raw_decision, :approved) == true
      return {action: :allow} if approved

      message = hash_value(raw_decision, :message) || "Approval denied for tool '#{tool_name}'"
      type = hash_value(raw_decision, :type) || :approval_denied
      {action: :deny, type: type.to_sym, message: message.to_s}
    else
      {
        action: :deny,
        type: :approval_error,
        message: "approval_callback returned unsupported decision for tool '#{tool_name}'"
      }
    end
  end

  #: (Symbol) -> Symbol
  def default_policy_type_for(action)
    case action
    when :allow
      :policy_allowed
    when :require_approval
      :approval_required
    else
      :policy_denied
    end
  end

  #: (Symbol) -> String
  def default_policy_message_for(action)
    case action
    when :allow
      "Tool dispatch allowed by policy"
    when :require_approval
      "Tool dispatch requires approval"
    else
      "Tool dispatch denied by policy"
    end
  end

  #: (Hash[Symbol | String, untyped], Symbol) -> untyped
  def hash_value(hash, key)
    return hash[key] if hash.key?(key)

    hash[key.to_s]
  end

  #: (type: Symbol, message: String) -> Riffer::Tools::Response
  def policy_error_response(type:, message:)
    Riffer::Tools::Response.error(message, type: type)
  end

  #: (tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped]) -> Riffer::Tools::Response
  def execute_tool_call_with_strategy(tool_call_event:, tool_class:, schema_tool:, arguments:)
    if @tool_executor
      return normalize_tool_executor_result(
        @tool_executor.call(
          tool_call_event: tool_call_event,
          tool_class: tool_class,
          arguments: arguments,
          context: @tool_context,
          agent: self
        )
      )
    end

    if tool_class
      return tool_class.new.call_with_validation(context: @tool_context, **arguments)
    end

    if schema_tool
      return Riffer::Tools::Response.error(
        "Tool '#{tool_call_event.name}' was declared as a schema Hash and requires tool_executor",
        type: :external_tool_executor_required
      )
    end

    Riffer::Tools::Response.error(
      "Unknown tool '#{tool_call_event.name}'",
      type: :unknown_tool
    )
  end

  #: (untyped) -> Riffer::Tools::Response
  def normalize_tool_executor_result(result)
    return result if result.is_a?(Riffer::Tools::Response)

    Riffer::Tools::Response.success(result)
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

  #: (String) -> Hash[Symbol | String, untyped]?
  def find_schema_tool(name)
    @connected_tools.find do |tool|
      next false unless tool.is_a?(Hash)

      schema_tool_names(tool).include?(name)
    end
  end

  #: (Hash[String, untyped]) -> Hash[Symbol, untyped]
  def parse_tool_arguments(arguments)
    return {} if arguments.empty?

    arguments.each_with_object({}) do |(key, value), result|
      result[key.to_sym] = value
    end
  end

  #: (Hash[Symbol | String, untyped]) -> Array[String]
  def schema_tool_names(schema_tool)
    payload = deep_stringify(schema_tool)
    names = []
    names << payload["name"] if payload["name"].is_a?(String) && !payload["name"].empty?
    if payload["function"].is_a?(Hash) && payload["function"]["name"].is_a?(String)
      names << payload["function"]["name"]
    end
    if payload["functionDeclarations"].is_a?(Array)
      payload["functionDeclarations"].each do |declaration|
        name = declaration.is_a?(Hash) ? declaration["name"] : nil
        names << name if name.is_a?(String) && !name.empty?
      end
    end
    names.uniq
  end

  #: (untyped) -> untyped
  def deep_stringify(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested), result|
        result[key.to_s] = deep_stringify(nested)
      end
    when Array
      value.map { |nested| deep_stringify(nested) }
    else
      value
    end
  end

  #: (Symbol) { (Hash[Symbol, untyped]) -> void } -> self
  def register_tool_hook(kind, &block)
    raise Riffer::ArgumentError, "on_#{kind}_tool_execution requires a block" unless block_given?

    hooks = case kind
    when :before
      @before_tool_execution_hooks
    when :after
      @after_tool_execution_hooks
    when :error
      @tool_execution_error_hooks
    else
      raise Riffer::ArgumentError, "unknown tool hook kind: #{kind}"
    end
    hooks << block
    self
  end

  #: (Array[^(Hash[Symbol, untyped]) -> void], Hash[Symbol, untyped]) -> void
  def invoke_tool_hooks(hooks, payload)
    hooks.each { |hook| hook.call(payload) }
  end

  #: (Hash[Symbol, untyped], Riffer::Tools::Response, Exception) -> void
  def safely_invoke_tool_error_hooks(hook_payload, result, error)
    invoke_tool_hooks(@tool_execution_error_hooks, hook_payload.merge(result: result, error: error))
  rescue => hook_error
    raise Riffer::Error,
      "on_tool_execution_error callback failed for #{hook_payload[:tool_name]}: #{hook_error.class}: #{hook_error.message}"
  end

  #: ((String | Symbol)?) -> Hash[Symbol, untyped]
  def resolve_profile(profile_name)
    return {} if profile_name.nil?

    normalized_profile_name = normalize_profile_name!(profile_name, "profile")
    profiles = self.class.profiles
    resolved = profiles[normalized_profile_name]
    raise Riffer::ArgumentError, "unknown profile '#{profile_name}'" if resolved.nil?

    resolved
  end

  #: (String?, Hash[Symbol, untyped]) -> String
  def resolve_model(model_override, profile_config)
    return validate_resolved_model!(model_override) unless model_override.nil?
    if profile_config.key?(:model)
      profile_value = resolve_configured_value(profile_config[:model])
      return validate_resolved_model!(profile_value)
    end

    config = @model_config
    if config.is_a?(Proc)
      return validate_resolved_model!((config.arity == 0) ? config.call : config.call(@tool_context))
    end

    return validate_resolved_model!(config) if config

    raise Riffer::ArgumentError, "model must be provided or configured via .model"
  end

  #: (String?, Hash[Symbol, untyped]) -> String
  def resolve_system_prompt(system_prompt_override, profile_config)
    return validate_resolved_system_prompt!(system_prompt_override) unless system_prompt_override.nil?
    if profile_config.key?(:instructions)
      profile_value = resolve_configured_value(profile_config[:instructions])
      return validate_resolved_system_prompt!(profile_value)
    end
    return validate_resolved_system_prompt!(@instructions_text) unless @instructions_text.nil?

    raise Riffer::ArgumentError, "system_prompt must be provided or configured via .instructions"
  end

  #: (Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]?, Hash[Symbol, untyped]) -> Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]
  def resolve_tools(tools_override, profile_config)
    return validate_resolved_tools!(tools_override) unless tools_override.nil?
    if profile_config.key?(:tools)
      profile_value = resolve_configured_value(profile_config[:tools])
      return validate_resolved_tools!(profile_value)
    end

    config = @tools_config
    return [] if config.nil?

    if config.is_a?(Proc)
      return validate_resolved_tools!((config.arity == 0) ? config.call : config.call(@tool_context))
    end

    validate_resolved_tools!(config)
  end

  #: (Hash[Symbol | String, untyped]?, Hash[Symbol, untyped]) -> Hash[Symbol | String, untyped]
  def resolve_config(config_override, profile_config)
    base_config = deep_copy(@voice_config)
    if profile_config.key?(:voice_config)
      profile_voice_config = profile_config[:voice_config]
      raise Riffer::ArgumentError, "profile voice_config must be a Hash" unless profile_voice_config.is_a?(Hash)

      base_config = deep_merge(base_config, deep_copy(profile_voice_config))
    end
    return base_config if config_override.nil?
    raise Riffer::ArgumentError, "config must be a Hash" unless config_override.is_a?(Hash)

    deep_merge(base_config, config_override)
  end

  #: (Symbol?, Hash[Symbol, untyped]) -> Symbol
  def resolve_runtime(runtime_override, profile_config)
    runtime = runtime_override
    runtime = profile_config[:runtime] if runtime.nil? && profile_config.key?(:runtime)
    runtime = @runtime_config if runtime.nil?
    runtime = :auto if runtime.nil?
    unless Riffer::Voice::SUPPORTED_RUNTIMES.include?(runtime)
      raise Riffer::ArgumentError, "runtime must be one of: #{Riffer::Voice::SUPPORTED_RUNTIMES.join(", ")}"
    end

    runtime
  end

  #: (Hash[Symbol | String, untyped]?, Hash[Symbol, untyped]) -> Hash[Symbol, Integer?]
  def resolve_action_budget(action_budget_override, profile_config)
    base_budget = deep_copy(@action_budget || {})
    if profile_config.key?(:action_budget)
      profile_budget = validate_action_budget_config!(profile_config[:action_budget], "profile action_budget")
      base_budget = deep_merge(base_budget, profile_budget)
    end

    return base_budget if action_budget_override.nil?

    override_budget = validate_action_budget_config!(action_budget_override, "action_budget")
    deep_merge(base_budget, override_budget)
  end

  #: (untyped, Hash[Symbol, untyped]) -> untyped
  def resolve_mutation_classifier(classifier_override, profile_config)
    return classifier_override unless classifier_override.nil?
    return profile_config[:mutation_classifier] if profile_config.key?(:mutation_classifier)

    @mutation_classifier
  end

  #: (untyped, Hash[Symbol, untyped]) -> untyped
  def resolve_tool_policy(policy_override, profile_config)
    return policy_override unless policy_override.nil?
    return profile_config[:tool_policy] if profile_config.key?(:tool_policy)

    @tool_policy
  end

  #: (untyped, Hash[Symbol, untyped]) -> untyped
  def resolve_approval_callback(approval_override, profile_config)
    return approval_override unless approval_override.nil?
    return profile_config[:approval_callback] if profile_config.key?(:approval_callback)

    @approval_callback
  end

  #: (untyped) -> untyped
  def resolve_configured_value(value)
    return value unless value.is_a?(Proc)

    (value.arity == 0) ? value.call : value.call(@tool_context)
  end

  #: (untyped, String) -> Symbol
  def normalize_profile_name!(profile_name, argument_name)
    case profile_name
    when Symbol
      profile_name
    when String
      stripped = profile_name.strip
      raise Riffer::ArgumentError, "#{argument_name} must be a non-empty String or Symbol" if stripped.empty?

      stripped.to_sym
    else
      raise Riffer::ArgumentError, "#{argument_name} must be a non-empty String or Symbol"
    end
  end

  #: (untyped, String) -> void
  def validate_tool_executor!(executor, argument_name)
    raise Riffer::ArgumentError, "#{argument_name} must respond to #call" unless executor.respond_to?(:call)
  end

  #: (untyped, String) -> void
  def validate_callable!(callable, argument_name)
    raise Riffer::ArgumentError, "#{argument_name} must respond to #call" unless callable.respond_to?(:call)
  end

  #: (untyped, String) -> Hash[Symbol, Integer?]
  def validate_action_budget_config!(config, argument_name)
    raise Riffer::ArgumentError, "#{argument_name} must be a Hash" unless config.is_a?(Hash)

    normalized = {}
    config.each do |raw_key, raw_value|
      key = raw_key.to_sym
      unless [:max_tool_calls, :max_mutation_calls].include?(key)
        raise Riffer::ArgumentError,
          "#{argument_name} supports only :max_tool_calls and :max_mutation_calls"
      end
      invalid_value = !raw_value.nil? && (!raw_value.is_a?(Integer) || raw_value <= 0)
      raise Riffer::ArgumentError, "#{argument_name}[#{key}] must be nil or an Integer > 0" if invalid_value

      normalized[key] = raw_value
    end

    normalized
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

  #: (untyped) -> Symbol
  def self.normalize_profile_name!(name)
    case name
    when Symbol
      name
    when String
      stripped = name.strip
      raise Riffer::ArgumentError, "profile name must be a non-empty String or Symbol" if stripped.empty?

      stripped.to_sym
    else
      raise Riffer::ArgumentError, "profile name must be a non-empty String or Symbol"
    end
  end
  private_class_method :normalize_profile_name!

  #: (untyped, String) -> Hash[Symbol, Integer?]
  def self.validate_action_budget_config!(config, argument_name)
    raise Riffer::ArgumentError, "#{argument_name} must be a Hash" unless config.is_a?(Hash)

    normalized = {}
    config.each do |raw_key, raw_value|
      key = raw_key.to_sym
      unless [:max_tool_calls, :max_mutation_calls].include?(key)
        raise Riffer::ArgumentError,
          "#{argument_name} supports only :max_tool_calls and :max_mutation_calls"
      end
      invalid_value = !raw_value.nil? && (!raw_value.is_a?(Integer) || raw_value <= 0)
      raise Riffer::ArgumentError, "#{argument_name}[#{key}] must be nil or an Integer > 0" if invalid_value

      normalized[key] = raw_value
    end

    normalized
  end
  private_class_method :validate_action_budget_config!

  # Internal profile DSL builder.
  class ProfileDefinition
    #: () -> void
    def initialize
      @settings = {}
    end

    #: (?(String | Proc)?) -> (String | Proc)?
    def model(model_string_or_proc = nil)
      return @settings[:model] if model_string_or_proc.nil?
      valid_model_value = model_string_or_proc.is_a?(String) || model_string_or_proc.is_a?(Proc)
      raise Riffer::ArgumentError, "profile model must be a String or Proc" unless valid_model_value

      @settings[:model] = model_string_or_proc
    end

    #: (?String?) -> String?
    def instructions(instructions_text = nil)
      return @settings[:instructions] if instructions_text.nil?
      raise Riffer::ArgumentError, "profile instructions must be a String" unless instructions_text.is_a?(String)

      @settings[:instructions] = instructions_text
    end

    #: (?(Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]] | Proc)?) -> (Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]] | Proc)?
    def uses_tools(tools_or_lambda = nil)
      return @settings[:tools] if tools_or_lambda.nil?
      valid_tools_or_lambda = tools_or_lambda.is_a?(Array) || tools_or_lambda.is_a?(Proc)
      raise Riffer::ArgumentError, "profile uses_tools must be an Array or Proc" unless valid_tools_or_lambda

      @settings[:tools] = tools_or_lambda
    end

    #: (?Symbol?) -> Symbol?
    def runtime(mode = nil)
      return @settings[:runtime] if mode.nil?
      unless Riffer::Voice::SUPPORTED_RUNTIMES.include?(mode)
        raise Riffer::ArgumentError, "runtime must be one of: #{Riffer::Voice::SUPPORTED_RUNTIMES.join(", ")}"
      end

      @settings[:runtime] = mode
    end

    #: (?Hash[Symbol | String, untyped]?) -> Hash[Symbol | String, untyped]
    def voice_config(config = nil)
      return deep_copy(@settings[:voice_config] || {}) if config.nil?
      raise Riffer::ArgumentError, "profile voice_config must be a Hash" unless config.is_a?(Hash)

      @settings[:voice_config] = deep_copy(config)
    end

    #: (?(^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped)?) -> ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped
    def tool_executor(executor = nil)
      return @settings[:tool_executor] if executor.nil?
      raise Riffer::ArgumentError, "profile tool_executor must respond to #call" unless executor.respond_to?(:call)

      @settings[:tool_executor] = executor
    end

    # Sets budget constraints for automatic tool dispatch in this profile.
    #
    #: (**untyped) -> Hash[Symbol, Integer?]
    def action_budget(**kwargs)
      return deep_copy(@settings[:action_budget] || {}) if kwargs.empty?
      raise Riffer::ArgumentError, "profile action_budget must include settings" if kwargs.empty?

      normalized = validate_action_budget_config!(kwargs, "profile action_budget")
      @settings[:action_budget] = normalized
    end

    #: (?(^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> bool)?) -> ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> bool
    def mutation_classifier(classifier = nil)
      return @settings[:mutation_classifier] if classifier.nil?
      raise Riffer::ArgumentError, "profile mutation_classifier must respond to #call" unless classifier.respond_to?(:call)

      @settings[:mutation_classifier] = classifier
    end

    #: (?(^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped)?) -> ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped
    def tool_policy(policy = nil)
      return @settings[:tool_policy] if policy.nil?
      raise Riffer::ArgumentError, "profile tool_policy must respond to #call" unless policy.respond_to?(:call)

      @settings[:tool_policy] = policy
    end

    #: (?(^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent, decision: Hash[Symbol, untyped]) -> untyped)?) -> ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent, decision: Hash[Symbol, untyped]) -> untyped
    def approval_callback(callback = nil)
      return @settings[:approval_callback] if callback.nil?
      raise Riffer::ArgumentError, "profile approval_callback must respond to #call" unless callback.respond_to?(:call)

      @settings[:approval_callback] = callback
    end

    #: () -> Hash[Symbol, untyped]
    def to_h
      deep_copy(@settings)
    end

    private

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

    #: (untyped, String) -> Hash[Symbol, Integer?]
    def validate_action_budget_config!(config, argument_name)
      raise Riffer::ArgumentError, "#{argument_name} must be a Hash" unless config.is_a?(Hash)

      normalized = {}
      config.each do |raw_key, raw_value|
        key = raw_key.to_sym
        unless [:max_tool_calls, :max_mutation_calls].include?(key)
          raise Riffer::ArgumentError,
            "#{argument_name} supports only :max_tool_calls and :max_mutation_calls"
        end
        invalid_value = !raw_value.nil? && (!raw_value.is_a?(Integer) || raw_value <= 0)
        raise Riffer::ArgumentError, "#{argument_name}[#{key}] must be nil or an Integer > 0" if invalid_value

        normalized[key] = raw_value
      end

      normalized
    end
  end

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
