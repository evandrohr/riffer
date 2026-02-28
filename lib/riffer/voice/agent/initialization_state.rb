# frozen_string_literal: true
# rbs_inline: enabled

# Internal initialization resolver for Riffer::Voice::Agent.
class Riffer::Voice::Agent::InitializationState
  #: (agent_class: singleton(Riffer::Voice::Agent), tool_context: Hash[Symbol, untyped]?, auto_handle_tool_calls: bool?, tool_executor: untyped, action_budget: Hash[Symbol | String, untyped]?, mutation_classifier: untyped, tool_policy: untyped, approval_callback: untyped) -> Hash[Symbol, untyped]
  def self.build(
    agent_class:,
    tool_context:,
    auto_handle_tool_calls:,
    tool_executor:,
    action_budget:,
    mutation_classifier:,
    tool_policy:,
    approval_callback:
  )
    validate_tool_context!(tool_context)
    validate_auto_handle_tool_calls!(auto_handle_tool_calls)
    validate_tool_executor!(tool_executor, "tool_executor") unless tool_executor.nil?
    validate_callable!(mutation_classifier, "mutation_classifier") unless mutation_classifier.nil?
    validate_callable!(tool_policy, "tool_policy") unless tool_policy.nil?
    validate_callable!(approval_callback, "approval_callback") unless approval_callback.nil?

    resolved_auto_handle_tool_calls = auto_handle_tool_calls.nil? ? agent_class.auto_handle_tool_calls : auto_handle_tool_calls
    resolved_action_budget = if action_budget.nil?
      agent_class.action_budget
    else
      validate_action_budget_config!(agent_class, action_budget, "action_budget")
    end

    {
      tool_context: tool_context,
      auto_handle_tool_calls: resolved_auto_handle_tool_calls,
      model_config: agent_class.model,
      instructions_text: agent_class.instructions,
      tools_config: agent_class.uses_tools,
      tool_executor: tool_executor || agent_class.tool_executor,
      action_budget: resolved_action_budget,
      mutation_classifier: mutation_classifier || agent_class.mutation_classifier,
      tool_policy: tool_policy || agent_class.tool_policy,
      approval_callback: approval_callback || agent_class.approval_callback,
      runtime_config: agent_class.runtime,
      voice_config: agent_class.voice_config
    }
  end

  #: (Hash[Symbol, untyped]?) -> void
  def self.validate_tool_context!(tool_context)
    return if tool_context.nil? || tool_context.is_a?(Hash)

    raise Riffer::ArgumentError, "tool_context must be a Hash or nil"
  end
  private_class_method :validate_tool_context!

  #: (bool?) -> void
  def self.validate_auto_handle_tool_calls!(auto_handle_tool_calls)
    return if auto_handle_tool_calls.nil? || auto_handle_tool_calls == true || auto_handle_tool_calls == false

    raise Riffer::ArgumentError, "auto_handle_tool_calls must be true, false, or nil"
  end
  private_class_method :validate_auto_handle_tool_calls!

  #: (untyped, String) -> void
  def self.validate_tool_executor!(tool_executor, argument_name)
    raise Riffer::ArgumentError, "#{argument_name} must respond to #call" unless tool_executor.respond_to?(:call)
  end
  private_class_method :validate_tool_executor!

  #: (untyped, String) -> void
  def self.validate_callable!(callable, argument_name)
    raise Riffer::ArgumentError, "#{argument_name} must respond to #call" unless callable.respond_to?(:call)
  end
  private_class_method :validate_callable!

  #: (singleton(Riffer::Voice::Agent), Hash[Symbol | String, untyped], String) -> Hash[Symbol, Integer?]
  def self.validate_action_budget_config!(agent_class, action_budget, argument_name)
    agent_class.send(:validate_action_budget_config!, action_budget, argument_name)
  end
  private_class_method :validate_action_budget_config!
end
