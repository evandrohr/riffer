# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::OpenaiRealtimeSessionConfig
  private

  #: (system_prompt: String, tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]], config: Hash[Symbol | String, untyped]) -> Hash[String, untyped]
  def build_session_update_payload(system_prompt:, tools:, config:)
    session = {
      "type" => "realtime",
      "model" => model,
      "instructions" => system_prompt,
      "output_modalities" => Riffer::Voice::Drivers::OpenAIRealtime::DEFAULT_OUTPUT_MODALITIES,
      "audio" => {
        "input" => {
          "format" => {
            "type" => Riffer::Voice::Drivers::OpenAIRealtime::DEFAULT_AUDIO_FORMAT_TYPE,
            "rate" => Riffer::Voice::Drivers::OpenAIRealtime::DEFAULT_AUDIO_SAMPLE_RATE
          },
          "transcription" => {
            "model" => Riffer::Voice::Drivers::OpenAIRealtime::DEFAULT_INPUT_TRANSCRIPTION_MODEL
          },
          "turn_detection" => {
            "type" => "semantic_vad",
            "create_response" => true,
            "interrupt_response" => false
          }
        },
        "output" => {
          "voice" => Riffer::Voice::Drivers::OpenAIRealtime::DEFAULT_OUTPUT_VOICE,
          "format" => {
            "type" => Riffer::Voice::Drivers::OpenAIRealtime::DEFAULT_AUDIO_FORMAT_TYPE,
            "rate" => Riffer::Voice::Drivers::OpenAIRealtime::DEFAULT_AUDIO_SAMPLE_RATE
          }
        }
      }
    }

    normalized_tools = normalize_openai_tools(tools)
    session["tools"] = normalized_tools unless normalized_tools.empty?
    session = merge_session_config(session: session, config: config)
    session = apply_configured_output_voice!(session: session)

    {
      "type" => "session.update",
      "session" => session
    }
  end

  #: (session: Hash[String, untyped], config: Hash[Symbol | String, untyped]) -> Hash[String, untyped]
  def merge_session_config(session:, config:)
    return session if config.empty?

    overrides = deep_stringify(config)

    if overrides.key?("voice")
      overrides = overrides.dup
      voice = overrides.delete("voice")
      overrides["audio"] ||= {}
      overrides["audio"]["output"] ||= {}
      overrides["audio"]["output"]["voice"] ||= voice
    end

    if overrides.key?("turn_detection")
      overrides = overrides.dup
      turn_detection = overrides.delete("turn_detection")
      overrides["audio"] ||= {}
      overrides["audio"]["input"] ||= {}
      overrides["audio"]["input"]["turn_detection"] ||= turn_detection
    end

    deep_merge(session, overrides)
  end

  #: (session: Hash[String, untyped]) -> Hash[String, untyped]
  def apply_configured_output_voice!(session:)
    voice = normalize_output_voice(session.dig("audio", "output", "voice"))
    session["audio"]["output"]["voice"] = voice
    @output_voice = voice
    session
  end

  #: (untyped) -> untyped
  def normalize_output_voice(value)
    if value.is_a?(Hash)
      normalized = deep_stringify(value)
      voice_id = normalized["id"]
      return normalized if voice_id.is_a?(String) && !voice_id.empty?

      raise Riffer::ArgumentError, "openai realtime custom voice must include a non-empty id"
    end

    voice = value.to_s
    valid_voices = Riffer::Voice::Drivers::OpenAIRealtime::VALID_OUTPUT_VOICES
    return voice if valid_voices.include?(voice)

    raise Riffer::ArgumentError,
      "openai realtime output voice must be one of: #{valid_voices.to_a.sort.join(", ")}"
  end

  #: (Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]) -> Array[Hash[String, untyped]]
  def normalize_openai_tools(tools)
    tools.filter_map do |tool|
      if tool.is_a?(Class) && tool <= Riffer::Tool
        sanitize_openai_tool({
          "type" => "function",
          "name" => tool.name,
          "description" => tool.description,
          "parameters" => tool.parameters_schema
        })
      elsif tool.is_a?(Hash)
        sanitize_openai_tool(stringify_hash(tool))
      end
    end
  end

  #: (Hash[String, untyped]) -> Hash[String, untyped]
  def sanitize_openai_tool(tool)
    sanitized_tool = sanitize_openai_schema_node(tool)
    sanitized_tool.reject { |key, _| key.to_s == "strict" }
  end

  #: (untyped) -> untyped
  def sanitize_openai_schema_node(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested), normalized|
        key_name = key.to_s
        normalized[key_name] = if key_name == "pattern" && nested.is_a?(String)
          normalize_openai_pattern(nested)
        else
          sanitize_openai_schema_node(nested)
        end
      end
    when Array
      value.map { |item| sanitize_openai_schema_node(item) }
    else
      value
    end
  end

  #: (String) -> String
  def normalize_openai_pattern(pattern)
    pattern.gsub("\\A", "^").gsub("\\z", "$").gsub("\\Z", "$")
  end
end
