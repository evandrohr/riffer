# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Agent::Utilities
  private

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

  #: (untyped, String) -> Integer
  def normalize_snapshot_counter!(value, field_name)
    invalid_value = !value.is_a?(Integer) || value.negative?
    raise Riffer::ArgumentError, "snapshot #{field_name} must be an Integer >= 0" if invalid_value

    value
  end
end
