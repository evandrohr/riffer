# frozen_string_literal: true
# rbs_inline: enabled

require "base64"
require "cgi"
require "json"

# Deepgram Voice Agent realtime voice driver.
class Riffer::Voice::Drivers::DeepgramVoiceAgent < Riffer::Voice::Drivers::Base
  include Riffer::Voice::Drivers::RuntimeSupport
  include Riffer::Voice::Drivers::DeepgramVoiceAgentLifecycle
  include Riffer::Voice::Drivers::DeepgramVoiceAgentConnection
  include Riffer::Voice::Drivers::DeepgramVoiceAgentDispatch

  DEFAULT_ENDPOINT = "wss://agent.deepgram.com/v1/agent/converse" #: String

  DEFAULT_MODEL = "gpt-4o-mini" #: String
  DEFAULT_LISTEN_MODEL = "flux-general-en" #: String
  DEFAULT_SPEAK_MODEL = "aura-2-asteria-en" #: String

  DEFAULT_INPUT_SAMPLE_RATE = 16_000 #: Integer
  DEFAULT_OUTPUT_SAMPLE_RATE = 24_000 #: Integer

  DEFAULT_INPUT_AUDIO_MIME_TYPE = "audio/pcm;rate=16000" #: String
  DEFAULT_OUTPUT_AUDIO_MIME_TYPE = "audio/pcm;rate=24000" #: String

  DEFAULT_AUTH_SCHEME = "token" #: String

  private

  #: (system_prompt: String, tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]) -> Hash[String, untyped]
  def default_settings_payload(system_prompt:, tools:)
    payload = {
      "type" => "Settings",
      "audio" => {
        "input" => {
          "encoding" => "linear16",
          "sample_rate" => DEFAULT_INPUT_SAMPLE_RATE
        },
        "output" => {
          "encoding" => "linear16",
          "sample_rate" => DEFAULT_OUTPUT_SAMPLE_RATE,
          "container" => "none"
        }
      },
      "agent" => {
        "listen" => {
          "provider" => {
            "type" => "deepgram",
            "model" => DEFAULT_LISTEN_MODEL
          }
        },
        "think" => {
          "provider" => {
            "type" => "open_ai",
            "model" => model
          },
          "prompt" => system_prompt
        },
        "speak" => {
          "provider" => {
            "type" => "deepgram",
            "model" => DEFAULT_SPEAK_MODEL
          }
        }
      }
    }

    normalized_tools = normalize_functions(tools)
    return payload if normalized_tools.empty?

    payload["agent"]["think"]["functions"] = normalized_tools
    payload
  end

  #: (Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]) -> Array[Hash[String, untyped]]
  def normalize_functions(tools)
    tools.flat_map do |tool|
      if tool.is_a?(Class) && tool <= Riffer::Tool
        [build_function_definition(
          "name" => tool.name,
          "description" => tool.description,
          "parameters" => deep_stringify(tool.parameters_schema)
        )]
      elsif tool.is_a?(Hash)
        normalize_hash_functions(tool)
      else
        []
      end
    end.compact
  end

  #: (Hash[Symbol | String, untyped]) -> Array[Hash[String, untyped]]
  def normalize_hash_functions(tool)
    payload = deep_stringify(tool)

    if payload["functions"].is_a?(Array)
      return payload["functions"].filter_map do |entry|
        build_function_definition(entry)
      end
    end

    if payload["functionDeclarations"].is_a?(Array)
      return payload["functionDeclarations"].filter_map do |entry|
        build_function_definition(entry)
      end
    end

    if payload["type"].to_s == "function" && payload["function"].is_a?(Hash)
      return [build_function_definition(payload["function"])].compact
    end

    [build_function_definition(payload)].compact
  end

  #: (Hash[String, untyped]) -> Hash[String, untyped]?
  def build_function_definition(payload)
    return nil unless payload.is_a?(Hash)

    name = payload["name"]
    parameters = payload["parameters"]
    return nil unless name.is_a?(String) && !name.empty?
    return nil unless parameters.is_a?(Hash)

    definition = {
      "name" => name,
      "parameters" => parameters
    }

    description = payload["description"]
    definition["description"] = description if description.is_a?(String) && !description.empty?

    endpoint = payload["endpoint"]
    definition["endpoint"] = endpoint if endpoint.is_a?(Hash)

    client_side = payload["client_side"]
    definition["client_side"] = client_side if client_side == true || client_side == false

    definition
  end

  #: (Hash[String, untyped]) -> String
  def output_audio_mime_type_from_settings(settings_payload)
    output = settings_payload.dig("audio", "output")
    return DEFAULT_OUTPUT_AUDIO_MIME_TYPE unless output.is_a?(Hash)

    encoding = output["encoding"].to_s
    sample_rate = output["sample_rate"]

    mime = if encoding == "linear16" || encoding.empty?
      "audio/pcm"
    else
      "audio/#{encoding}"
    end

    return mime unless sample_rate

    "#{mime};rate=#{sample_rate}"
  end
end
