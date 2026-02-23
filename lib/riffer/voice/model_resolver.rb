# frozen_string_literal: true
# rbs_inline: enabled

# Resolves voice model identifiers into provider adapter configuration.
class Riffer::Voice::ModelResolver
  RESOLUTIONS = {
    "openai" => {
      adapter_identifier: :openai_realtime,
      config_key: :openai
    },
    "gemini" => {
      adapter_identifier: :gemini_live,
      config_key: :gemini
    }
  }.freeze #: Hash[String, Hash[Symbol, Symbol]]

  LEGACY_PROVIDERS = ["openai_realtime", "gemini_live"].freeze #: Array[String]

  #: (model: String, ?validate_config: bool) -> Hash[Symbol, String | Symbol]
  def self.resolve(model:, validate_config: true)
    provider, provider_model = parse_model(model)

    resolution = RESOLUTIONS[provider]
    unless resolution
      supported = RESOLUTIONS.keys.join(", ")
      raise Riffer::ArgumentError, "unsupported voice provider '#{provider}'. Supported providers: #{supported}"
    end

    validate_provider_configuration!(provider: provider, config_key: resolution[:config_key]) if validate_config

    {
      provider: provider,
      adapter_identifier: resolution[:adapter_identifier],
      model: provider_model
    }
  end

  #: (String) -> [String, String]
  def self.parse_model(model)
    raise Riffer::ArgumentError, "voice model must be a non-empty String" unless model.is_a?(String) && !model.empty?
    raise Riffer::ArgumentError, "voice model must use provider/model format" unless model.include?("/")

    provider, provider_model = model.split("/", 2)
    if provider.nil? || provider.empty? || provider_model.nil? || provider_model.empty?
      raise Riffer::ArgumentError, "voice model must use provider/model format"
    end

    if LEGACY_PROVIDERS.include?(provider)
      raise Riffer::ArgumentError, "legacy voice model prefix '#{provider}' is no longer supported; use provider/model (openai/... or gemini/...)"
    end

    [provider, provider_model]
  end
  private_class_method :parse_model

  #: (provider: String, config_key: Symbol) -> void
  def self.validate_provider_configuration!(provider:, config_key:)
    provider_config = Riffer.config.public_send(config_key)
    api_key = provider_config&.api_key
    return if api_key.is_a?(String) && !api_key.empty?

    raise Riffer::ArgumentError, "#{provider} api_key is required to use #{provider}/* voice models"
  end
  private_class_method :validate_provider_configuration!
end
