# frozen_string_literal: true
# rbs_inline: enabled

# Base class for provider-specific realtime event parsers.
class Riffer::Voice::Parsers::Base
  #: (Hash[Symbol | String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def call(payload)
    raise NotImplementedError, "Subclasses must implement #call"
  end

  private

  #: (Hash[Symbol | String, untyped]) -> Hash[String, untyped]
  def normalize_hash(payload)
    deep_stringify(payload)
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

  #: (Hash[String, untyped], Array[String]) -> untyped
  def fetch_any(hash, keys)
    keys.each do |key|
      return hash[key] if hash.key?(key)
    end
    nil
  end

  #: (Hash[String, untyped], Array[String]) -> bool
  def true_any?(hash, keys)
    keys.any? { |key| hash[key] == true }
  end

  #: (Hash[String, untyped]) -> Hash[Symbol, untyped]
  def symbolize_hash(hash)
    hash.each_with_object({}) do |(key, value), result|
      result[key.to_sym] = value
    end
  end
end
