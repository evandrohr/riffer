# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Agent::SessionLifecycle
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
    reset_existing_session!
    profile_config = resolve_profile(profile)
    assign_active_profile(profile)
    apply_dispatch_configuration!(
      profile_config: profile_config,
      tool_executor: tool_executor,
      action_budget: action_budget,
      mutation_classifier: mutation_classifier,
      tool_policy: tool_policy,
      approval_callback: approval_callback
    )

    connect_payload = resolve_connect_payload(
      model: model,
      system_prompt: system_prompt,
      tools: tools,
      config: config,
      runtime: runtime,
      profile_config: profile_config
    )

    @session = Riffer::Voice.connect(**connect_payload, adapter_factory: adapter_factory)
    @connected_tools = connect_payload[:tools]
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

  #: () -> void
  def close
    return if @session.nil?

    @session.close
  end

  private

  #: () -> void
  def reset_existing_session!
    close if @session && !@session.closed?
  end

  #: ((String | Symbol)?) -> void
  def assign_active_profile(profile)
    @active_profile = profile.nil? ? nil : normalize_profile_name!(profile, "profile")
  end

  #: (profile_config: Hash[Symbol, untyped], tool_executor: untyped, action_budget: Hash[Symbol | String, untyped]?, mutation_classifier: untyped, tool_policy: untyped, approval_callback: untyped) -> void
  def apply_dispatch_configuration!(
    profile_config:,
    tool_executor:,
    action_budget:,
    mutation_classifier:,
    tool_policy:,
    approval_callback:
  )
    apply_tool_executor_override(tool_executor, profile_config)
    @action_budget = resolve_action_budget(action_budget, profile_config)
    @mutation_classifier = resolve_mutation_classifier(mutation_classifier, profile_config)
    @tool_policy = resolve_tool_policy(tool_policy, profile_config)
    @approval_callback = resolve_approval_callback(approval_callback, profile_config)
    validate_callable!(@mutation_classifier, "mutation_classifier") unless @mutation_classifier.nil?
    validate_callable!(@tool_policy, "tool_policy") unless @tool_policy.nil?
    validate_callable!(@approval_callback, "approval_callback") unless @approval_callback.nil?
    @tool_call_count = 0
    @mutation_tool_call_count = 0
  end

  #: (untyped, Hash[Symbol, untyped]) -> void
  def apply_tool_executor_override(tool_executor, profile_config)
    unless tool_executor.nil?
      validate_tool_executor!(tool_executor, "tool_executor")
      @tool_executor = tool_executor
      return
    end

    return unless profile_config.key?(:tool_executor)

    profile_tool_executor = profile_config[:tool_executor]
    validate_tool_executor!(profile_tool_executor, "profile tool_executor")
    @tool_executor = profile_tool_executor
  end

  #: (model: String?, system_prompt: String?, tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]?, config: Hash[Symbol | String, untyped]?, runtime: Symbol?, profile_config: Hash[Symbol, untyped]) -> Hash[Symbol, untyped]
  def resolve_connect_payload(model:, system_prompt:, tools:, config:, runtime:, profile_config:)
    resolved_tools = resolve_tools(tools, profile_config)

    {
      model: resolve_model(model, profile_config),
      system_prompt: resolve_system_prompt(system_prompt, profile_config),
      tools: resolved_tools,
      config: resolve_config(config, profile_config),
      runtime: resolve_runtime(runtime, profile_config)
    }
  end

  #: () -> Riffer::Voice::Session
  def current_session
    session = @session
    raise Riffer::Error, "Voice agent is not connected" if session.nil?

    session
  end
end
