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

  include Riffer::Voice::Agent::Utilities
  include Riffer::Voice::Agent::Callbacks
  include Riffer::Voice::Agent::Policy
  include Riffer::Voice::Agent::ToolExecution
  include Riffer::Voice::Agent::Resolution

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

  CHECKPOINT_KEYS = [
    :on_checkpoint,
    :on_turn_complete_checkpoint,
    :on_tool_request_checkpoint,
    :on_tool_response_checkpoint,
    :on_recoverable_error_checkpoint
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
    @checkpoint_callbacks = default_checkpoint_callbacks #: Hash[Symbol, Array[^(Hash[Symbol, untyped]) -> void]]
    @before_tool_execution_hooks = [] #: Array[^(Hash[Symbol, untyped]) -> void]
    @after_tool_execution_hooks = [] #: Array[^(Hash[Symbol, untyped]) -> void]
    @tool_execution_error_hooks = [] #: Array[^(Hash[Symbol, untyped]) -> void]
    @tool_call_count = 0
    @mutation_tool_call_count = 0
    @active_profile = nil
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
    @active_profile = profile.nil? ? nil : normalize_profile_name!(profile, "profile")

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

  # Exports lightweight orchestration metadata for app-managed resume.
  #
  #: () -> Hash[Symbol, untyped]
  def export_state_snapshot
    {
      active_profile: @active_profile,
      auto_handle_tool_calls: @auto_handle_tool_calls,
      action_budget: deep_copy(@action_budget),
      tool_call_count: @tool_call_count,
      mutation_tool_call_count: @mutation_tool_call_count
    }
  end

  # Imports lightweight orchestration metadata for app-managed resume.
  #
  #: (snapshot: Hash[Symbol | String, untyped]) -> self
  def import_state_snapshot(snapshot:)
    raise Riffer::ArgumentError, "snapshot must be a Hash" unless snapshot.is_a?(Hash)

    normalized = deep_stringify(snapshot)
    if normalized.key?("auto_handle_tool_calls")
      value = normalized["auto_handle_tool_calls"]
      valid_value = value == true || value == false
      raise Riffer::ArgumentError, "snapshot auto_handle_tool_calls must be true or false" unless valid_value

      @auto_handle_tool_calls = value
    end
    if normalized.key?("action_budget")
      @action_budget = validate_action_budget_config!(normalized["action_budget"], "snapshot action_budget")
    end
    if normalized.key?("tool_call_count")
      @tool_call_count = normalize_snapshot_counter!(normalized["tool_call_count"], "tool_call_count")
    end
    if normalized.key?("mutation_tool_call_count")
      @mutation_tool_call_count = normalize_snapshot_counter!(normalized["mutation_tool_call_count"], "mutation_tool_call_count")
    end
    if normalized.key?("active_profile")
      profile_value = normalized["active_profile"]
      @active_profile = profile_value.nil? ? nil : normalize_profile_name!(profile_value, "snapshot active_profile")
    end

    self
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

  #: (Riffer::Voice::Events::Base, auto_handle_tool_calls: bool) -> Riffer::Voice::Events::Base
  def consume_event(event, auto_handle_tool_calls:)
    handle_tool_call_event(event) if auto_handle_tool_calls
    dispatch_event_callbacks(event)
    emit_checkpoint(:turn_complete, {event: event}) if event.is_a?(Riffer::Voice::Events::TurnComplete)
    event
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
end
