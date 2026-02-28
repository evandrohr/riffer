# frozen_string_literal: true
# rbs_inline: enabled

# Internal profile DSL builder for Riffer::Voice::Agent profiles.
class Riffer::Voice::Agent::ProfileDefinition
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
