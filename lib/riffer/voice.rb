# frozen_string_literal: true
# rbs_inline: enabled

# Namespace for realtime voice abstractions in the Riffer framework.
#
# Voice support is additive and provider-neutral.
module Riffer::Voice
  SUPPORTED_RUNTIMES = [:auto, :async, :background].freeze #: Array[Symbol]

  #: (model: String, system_prompt: String, ?tools: Array[singleton(Riffer::Tool)], ?config: Hash[Symbol | String, untyped], ?runtime: Symbol) -> Riffer::Voice::Session
  def self.connect(model:, system_prompt:, tools: [], config: {}, runtime: :auto)
    validate_connect_input!(model: model, system_prompt: system_prompt, tools: tools, config: config, runtime: runtime)
    Riffer::Voice::Session.new(
      model: model,
      system_prompt: system_prompt,
      tools: tools,
      config: config,
      runtime: runtime
    )
  end

  #: (model: String, system_prompt: String, tools: Array[singleton(Riffer::Tool)], config: Hash[Symbol | String, untyped], runtime: Symbol) -> void
  def self.validate_connect_input!(model:, system_prompt:, tools:, config:, runtime:)
    raise Riffer::ArgumentError, "model must be a non-empty String" unless model.is_a?(String) && !model.empty?
    raise Riffer::ArgumentError, "system_prompt must be a non-empty String" unless system_prompt.is_a?(String) && !system_prompt.empty?
    raise Riffer::ArgumentError, "tools must be an Array" unless tools.is_a?(Array)
    raise Riffer::ArgumentError, "config must be a Hash" unless config.is_a?(Hash)
    raise Riffer::ArgumentError, "runtime must be one of: #{SUPPORTED_RUNTIMES.join(", ")}" unless SUPPORTED_RUNTIMES.include?(runtime)
  end
  private_class_method :validate_connect_input!
end
