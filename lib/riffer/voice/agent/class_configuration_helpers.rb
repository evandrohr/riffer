# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Agent::ClassConfigurationHelpers
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

  #: (untyped) -> Symbol
  def normalize_profile_name!(name)
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
