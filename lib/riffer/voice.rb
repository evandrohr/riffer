# frozen_string_literal: true
# rbs_inline: enabled

# Namespace for realtime voice abstractions in the Riffer framework.
#
# Voice support is additive and provider-neutral.
module Riffer::Voice
  SUPPORTED_RUNTIMES = [:auto, :async, :background].freeze #: Array[Symbol]

  #: (model: String, system_prompt: String, ?tools: Array[singleton(Riffer::Tool)], ?config: Hash[Symbol | String, untyped], ?runtime: Symbol, ?adapter_factory: ^(adapter_identifier: Symbol, model: String, runtime_executor: (Riffer::Voice::Runtime::ManagedAsync | Riffer::Voice::Runtime::BackgroundAsync)) -> untyped) -> Riffer::Voice::Session
  def self.connect(model:, system_prompt:, tools: [], config: {}, runtime: :auto, adapter_factory: nil)
    validate_connect_input!(
      model: model,
      system_prompt: system_prompt,
      tools: tools,
      config: config,
      runtime: runtime,
      adapter_factory: adapter_factory
    )
    runtime_executor = Riffer::Voice::Runtime::Resolver.resolve(requested_mode: runtime)
    begin
      resolved_model = Riffer::Voice::ModelResolver.resolve(model: model, validate_config: adapter_factory.nil?)
      adapter = build_adapter(
        adapter_identifier: resolved_model[:adapter_identifier],
        model: resolved_model[:model],
        runtime_executor: runtime_executor,
        adapter_factory: adapter_factory
      )

      Riffer::Voice::Session.new(
        model: model,
        system_prompt: system_prompt,
        tools: tools,
        config: config,
        runtime: runtime,
        runtime_executor: runtime_executor,
        adapter: adapter
      )
    rescue
      begin
        runtime_executor.shutdown if runtime_executor.respond_to?(:shutdown)
      rescue => error
        Warning.warn("[riffer] runtime shutdown failed during voice.connect cleanup: #{error.class}: #{error.message}\n")
      end
      raise
    end
  end

  #: (model: String, system_prompt: String, tools: Array[singleton(Riffer::Tool)], config: Hash[Symbol | String, untyped], runtime: Symbol, adapter_factory: untyped) -> void
  def self.validate_connect_input!(model:, system_prompt:, tools:, config:, runtime:, adapter_factory:)
    raise Riffer::ArgumentError, "model must be a non-empty String" unless model.is_a?(String) && !model.empty?
    raise Riffer::ArgumentError, "system_prompt must be a non-empty String" unless system_prompt.is_a?(String) && !system_prompt.empty?
    raise Riffer::ArgumentError, "tools must be an Array" unless tools.is_a?(Array)
    raise Riffer::ArgumentError, "config must be a Hash" unless config.is_a?(Hash)
    raise Riffer::ArgumentError, "runtime must be one of: #{SUPPORTED_RUNTIMES.join(", ")}" unless SUPPORTED_RUNTIMES.include?(runtime)
    invalid_factory = !adapter_factory.nil? && !adapter_factory.respond_to?(:call)
    raise Riffer::ArgumentError, "adapter_factory must respond to #call" if invalid_factory
  end
  private_class_method :validate_connect_input!

  #: (adapter_identifier: Symbol, model: String, runtime_executor: (Riffer::Voice::Runtime::ManagedAsync | Riffer::Voice::Runtime::BackgroundAsync), adapter_factory: untyped) -> untyped
  def self.build_adapter(adapter_identifier:, model:, runtime_executor:, adapter_factory:)
    if adapter_factory
      return adapter_factory.call(
        adapter_identifier: adapter_identifier,
        model: model,
        runtime_executor: runtime_executor
      )
    end

    adapter_class = Riffer::Voice::Adapters::Repository.find(adapter_identifier)
    unless adapter_class
      raise Riffer::ArgumentError, "unsupported voice adapter identifier: #{adapter_identifier}"
    end

    adapter_class.new(model: model, runtime_executor: runtime_executor)
  end
  private_class_method :build_adapter
end
