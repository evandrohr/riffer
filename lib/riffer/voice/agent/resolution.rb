# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Agent::Resolution
  private

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
end
