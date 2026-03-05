# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::GeminiLivePayloads
  private

  #: (system_prompt: String, tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]], config: Hash[Symbol | String, untyped]) -> Hash[String, untyped]
  def build_setup_payload(system_prompt:, tools:, config:)
    payload = {
      "setup" => {
        "model" => normalized_model,
        "systemInstruction" => {
          "parts" => [{"text" => system_prompt}]
        }
      }
    }

    tool_declarations = normalize_gemini_tools(tools)
    payload["setup"]["tools"] = tool_declarations unless tool_declarations.empty?

    config_hash = normalize_connect_config(config)
    payload["setup"].merge!(config_hash) unless config_hash.empty?
    payload
  end

  #: (Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]) -> Array[Hash[String, untyped]]
  def normalize_gemini_tools(tools)
    declarations = tools.flat_map do |tool|
      if tool.is_a?(Class) && tool <= Riffer::Tool
        [
          sanitize_tool_definition(
            {
              "name" => tool.name,
              "description" => tool.description,
              "parameters" => tool.parameters_schema
            }
          )
        ]
      elsif tool.is_a?(Hash)
        expand_hash_tool_definition(tool)
      else
        []
      end
    end

    return [] if declarations.empty?

    [{"functionDeclarations" => declarations}]
  end

  #: (Hash[Symbol | String, untyped]) -> Array[Hash[String, untyped]]
  def expand_hash_tool_definition(tool)
    payload = deep_stringify(tool)
    function_declarations = payload["functionDeclarations"]
    return [sanitize_tool_definition(payload)] unless function_declarations.is_a?(Array)

    function_declarations.filter_map do |definition|
      sanitize_tool_definition(definition) if definition.is_a?(Hash)
    end
  end

  #: (Hash[Symbol | String, untyped]) -> Hash[String, untyped]
  def normalize_connect_config(config)
    deep_merge(
      {
        "generationConfig" => {
          "responseModalities" => Riffer::Voice::Drivers::GeminiLive::DEFAULT_RESPONSE_MODALITIES.dup
        },
        "inputAudioTranscription" => {},
        "outputAudioTranscription" => {}
      },
      deep_stringify(config || {})
    )
  end

  #: () -> String
  def normalized_model
    value = model.to_s
    return value if value.start_with?("models/")

    "models/#{value}"
  end

  #: (Hash[String, untyped]) -> Hash[String, untyped]
  def sanitize_tool_definition(tool)
    sanitized = tool.dup
    parameters = sanitized["parameters"]
    sanitized["parameters"] = sanitize_schema(parameters) if parameters.is_a?(Hash)
    sanitized
  end

  #: (untyped) -> untyped
  def sanitize_schema(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested_value), normalized|
        string_key = key.to_s
        next if Riffer::Voice::Drivers::GeminiLive::UNSUPPORTED_SCHEMA_KEYS.include?(string_key)

        normalized[string_key] = sanitize_schema(nested_value)
      end
    when Array
      value.map { |item| sanitize_schema(item) }
    else
      value
    end
  end

  #: (call_id: String, result: untyped, ?default_name: String?) -> Hash[String, untyped]
  def normalize_tool_response_payload(call_id:, result:, default_name: nil)
    default_name_value = default_name.to_s
    unless result.is_a?(Hash)
      payload = {
        "id" => call_id,
        "response" => {"result" => result}
      }
      payload["name"] = default_name_value unless default_name_value.empty?
      return payload
    end

    payload = deep_stringify(result)
    tool_payload = {
      "id" => payload["id"].to_s.empty? ? call_id : payload["id"].to_s
    }

    name = payload["name"]
    name_value = name.to_s
    if name_value.empty?
      tool_name_value = payload["tool_name"].to_s
      name_value = tool_name_value.empty? ? default_name_value : tool_name_value
    end
    tool_payload["name"] = name_value unless name_value.empty?

    response_value = if payload.key?("response")
      payload["response"]
    else
      payload.reject { |key, _value| key == "id" || key == "name" || key == "tool_name" }
    end

    tool_payload["response"] = response_value.is_a?(Hash) ? response_value : {"result" => response_value}
    tool_payload
  end
end
