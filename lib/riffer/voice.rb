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
    validate_tools!(tools)
    raise Riffer::ArgumentError, "config must be a Hash" unless config.is_a?(Hash)
    raise Riffer::ArgumentError, "runtime must be one of: #{SUPPORTED_RUNTIMES.join(", ")}" unless SUPPORTED_RUNTIMES.include?(runtime)
    invalid_factory = !adapter_factory.nil? && !adapter_factory.respond_to?(:call)
    raise Riffer::ArgumentError, "adapter_factory must respond to #call" if invalid_factory
  end
  private_class_method :validate_connect_input!

  #: (Array[untyped]) -> void
  def self.validate_tools!(tools)
    tools.each_with_index do |tool, index|
      next if tool_class?(tool)
      next if valid_tool_schema_hash?(tool)

      raise Riffer::ArgumentError,
        "tools[#{index}] must be a Riffer::Tool class or a valid OpenAI/Gemini/Deepgram tool schema Hash"
    end
  end
  private_class_method :validate_tools!

  #: (untyped) -> bool
  def self.tool_class?(tool)
    tool.is_a?(Class) && tool <= Riffer::Tool
  end
  private_class_method :tool_class?

  #: (untyped) -> bool
  def self.valid_tool_schema_hash?(tool)
    return false unless tool.is_a?(Hash)

    payload = deep_stringify(tool)
    return false if payload.empty?

    valid_openai_tool_schema_hash?(payload) ||
      valid_gemini_tool_schema_hash?(payload) ||
      valid_deepgram_tool_schema_hash?(payload)
  end
  private_class_method :valid_tool_schema_hash?

  #: (Hash[String, untyped]) -> bool
  def self.valid_openai_tool_schema_hash?(payload)
    payload["type"].to_s == "function" &&
      non_empty_string?(payload["name"]) &&
      payload["parameters"].is_a?(Hash)
  end
  private_class_method :valid_openai_tool_schema_hash?

  #: (Hash[String, untyped]) -> bool
  def self.valid_gemini_tool_schema_hash?(payload)
    if payload["functionDeclarations"].is_a?(Array)
      declarations = payload["functionDeclarations"]
      return false if declarations.empty?

      return declarations.all? { |entry| valid_gemini_function_declaration?(entry) }
    end

    non_empty_string?(payload["name"]) && payload["parameters"].is_a?(Hash)
  end
  private_class_method :valid_gemini_tool_schema_hash?

  #: (untyped) -> bool
  def self.valid_gemini_function_declaration?(entry)
    entry.is_a?(Hash) &&
      non_empty_string?(entry["name"]) &&
      entry["parameters"].is_a?(Hash)
  end
  private_class_method :valid_gemini_function_declaration?

  #: (Hash[String, untyped]) -> bool
  def self.valid_deepgram_tool_schema_hash?(payload)
    functions = payload["functions"]
    if functions.is_a?(Array)
      return false if functions.empty?

      return functions.all? { |entry| valid_deepgram_function_definition?(entry) }
    end

    valid_deepgram_function_definition?(payload)
  end
  private_class_method :valid_deepgram_tool_schema_hash?

  #: (untyped) -> bool
  def self.valid_deepgram_function_definition?(entry)
    entry.is_a?(Hash) &&
      non_empty_string?(entry["name"]) &&
      entry["parameters"].is_a?(Hash)
  end
  private_class_method :valid_deepgram_function_definition?

  #: (untyped) -> bool
  def self.non_empty_string?(value)
    value.is_a?(String) && !value.empty?
  end
  private_class_method :non_empty_string?

  #: (untyped) -> untyped
  def self.deep_stringify(value)
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
  private_class_method :deep_stringify

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
