# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Agent::Policy
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

  private

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
end
