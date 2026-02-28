# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Agent::ClassToolDefaults
  include Riffer::Voice::Agent::ClassConfigurationHelpers

  UNSET = Object.new

  #: (?(String | Proc)?) -> (String | Proc)?
  def model(model_string_or_proc = UNSET)
    return @model if model_string_or_proc.equal?(UNSET)

    unless model_string_or_proc.is_a?(Proc)
      validate_is_string!(model_string_or_proc, "model")
    end

    @model = model_string_or_proc
  end

  #: (?String?) -> String?
  def instructions(instructions_text = UNSET)
    return @instructions if instructions_text.equal?(UNSET)

    validate_is_string!(instructions_text, "instructions")
    @instructions = instructions_text
  end

  #: (?(Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]] | Proc)?) -> (Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]] | Proc)?
  def uses_tools(tools_or_lambda = UNSET)
    return @tools_config if tools_or_lambda.equal?(UNSET)

    @tools_config = tools_or_lambda
  end

  # Gets or sets the default tool executor used by automatic ToolCall handling.
  #
  #: (?(^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped)?) -> ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped
  def tool_executor(executor = UNSET)
    read_or_assign_callable!(instance_variable_name: :@tool_executor, value: executor, argument_name: "tool_executor")
  end

  # Gets or sets action budget defaults enforced during automatic tool dispatch.
  #
  #: (**untyped) -> Hash[Symbol, Integer?]
  def action_budget(**kwargs)
    return deep_copy(@action_budget || {}) if kwargs.empty?

    @action_budget = validate_action_budget_config!(kwargs, "action_budget")
  end

  # Gets or sets the mutation classifier used by budget/policy checks.
  #
  #: (?(^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> bool)?) -> ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> bool
  def mutation_classifier(classifier = UNSET)
    read_or_assign_callable!(instance_variable_name: :@mutation_classifier, value: classifier, argument_name: "mutation_classifier")
  end

  # Gets or sets the dispatch policy hook used before automatic tool execution.
  #
  #: (?(^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped)?) -> ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent) -> untyped
  def tool_policy(policy = UNSET)
    read_or_assign_callable!(instance_variable_name: :@tool_policy, value: policy, argument_name: "tool_policy")
  end

  # Gets or sets the approval callback used for gated tool dispatch.
  #
  #: (?(^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent, decision: Hash[Symbol, untyped]) -> untyped)?) -> ^(tool_call_event: Riffer::Voice::Events::ToolCall, tool_name: String, tool_class: singleton(Riffer::Tool)?, schema_tool: Hash[Symbol | String, untyped]?, arguments: Hash[Symbol, untyped], mutation_call: bool, context: Hash[Symbol, untyped]?, agent: Riffer::Voice::Agent, decision: Hash[Symbol, untyped]) -> untyped
  def approval_callback(callback = UNSET)
    read_or_assign_callable!(instance_variable_name: :@approval_callback, value: callback, argument_name: "approval_callback")
  end

  private

  #: (instance_variable_name: Symbol, value: untyped, argument_name: String) -> untyped
  def read_or_assign_callable!(instance_variable_name:, value:, argument_name:)
    return instance_variable_get(instance_variable_name) if value.equal?(UNSET)
    raise Riffer::ArgumentError, "#{argument_name} must respond to #call" unless value.respond_to?(:call)

    instance_variable_set(instance_variable_name, value)
  end
end
