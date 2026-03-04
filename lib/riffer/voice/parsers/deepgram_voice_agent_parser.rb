# frozen_string_literal: true
# rbs_inline: enabled

require "json"

# Parses Deepgram Voice Agent payloads into normalized voice events.
class Riffer::Voice::Parsers::DeepgramVoiceAgentParser < Riffer::Voice::Parsers::Base
  FUNCTION_CALL_REQUEST_TYPES = ["FunctionCallRequest", "function_call_request"].freeze #: Array[String]
  FUNCTION_CALL_RESPONSE_TYPES = ["FunctionCallResponse", "function_call_response"].freeze #: Array[String]
  CONVERSATION_TEXT_TYPES = ["ConversationText", "conversation_text"].freeze #: Array[String]
  USER_STARTED_SPEAKING_TYPES = ["UserStartedSpeaking", "user_started_speaking"].freeze #: Array[String]
  AGENT_AUDIO_DONE_TYPES = ["AgentAudioDone", "agent_audio_done"].freeze #: Array[String]
  INJECTION_REFUSED_TYPES = ["InjectionRefused", "injection_refused"].freeze #: Array[String]
  ERROR_TYPES = ["Error", "error"].freeze #: Array[String]
  WARNING_TYPES = ["Warning", "warning"].freeze #: Array[String]

  KEYS_CALL_ID = ["id", "call_id", "callId"].freeze #: Array[String]
  KEYS_NAME = ["name", "function_name", "functionName"].freeze #: Array[String]
  KEYS_ITEM_ID = ["item_id", "itemId"].freeze #: Array[String]
  KEYS_ARGUMENTS = ["arguments", "args"].freeze #: Array[String]
  KEYS_CLIENT_SIDE = ["client_side", "clientSide"].freeze #: Array[String]

  KEYS_TEXT = ["content", "text", "transcript"].freeze #: Array[String]
  KEYS_FINAL = ["is_final", "isFinal", "final"].freeze #: Array[String]
  KEYS_ROLE = ["role"].freeze #: Array[String]

  KEYS_ERROR_CODE = ["code", "error_code", "errorCode"].freeze #: Array[String]
  KEYS_ERROR_MESSAGE = ["message", "description", "error_message", "errorMessage"].freeze #: Array[String]

  #: (Hash[Symbol | String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def call(payload)
    data = normalize_hash(payload)
    type = data["type"].to_s
    return [] if type.empty?

    return parse_function_call_request(data) if FUNCTION_CALL_REQUEST_TYPES.include?(type)
    return parse_function_call_response(data) if FUNCTION_CALL_RESPONSE_TYPES.include?(type)
    return parse_conversation_text(data) if CONVERSATION_TEXT_TYPES.include?(type)
    return [Riffer::Voice::Events::Interrupt.new(reason: "user_started_speaking")] if USER_STARTED_SPEAKING_TYPES.include?(type)
    return [Riffer::Voice::Events::TurnComplete.new(metadata: symbolize_hash(data))] if AGENT_AUDIO_DONE_TYPES.include?(type)
    return [parse_error_event(data, retriable: true, fallback_code: "injection_refused")] if INJECTION_REFUSED_TYPES.include?(type)
    return [parse_error_event(data, retriable: true)] if WARNING_TYPES.include?(type)
    return [parse_error_event(data, retriable: false)] if ERROR_TYPES.include?(type)

    []
  end

  private

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_function_call_request(data)
    functions = data["functions"]
    return [] unless functions.is_a?(Array)

    functions.filter_map do |entry|
      next unless entry.is_a?(Hash)

      function = normalize_hash(entry)
      next unless fetch_any(function, KEYS_CLIENT_SIDE) == true

      call_id = fetch_any(function, KEYS_CALL_ID)
      name = fetch_any(function, KEYS_NAME)
      next if call_id.to_s.empty? || name.to_s.empty?

      Riffer::Voice::Events::ToolCall.new(
        call_id: call_id.to_s,
        name: name.to_s,
        arguments: parse_arguments(fetch_any(function, KEYS_ARGUMENTS)),
        item_id: fetch_any(function, KEYS_ITEM_ID)&.to_s
      )
    end
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_function_call_response(data)
    content = data["content"]
    return [] if content.nil?

    text = if content.is_a?(String)
      content
    else
      JSON.generate(content)
    end
    return [] if text.empty?

    metadata = symbolize_hash(data).merge(function_call_response: true)
    [Riffer::Voice::Events::OutputTranscript.new(text: text, is_final: true, metadata: metadata)]
  rescue JSON::GeneratorError
    []
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_conversation_text(data)
    text = fetch_any(data, KEYS_TEXT)
    return [] if text.to_s.empty?

    role = fetch_any(data, KEYS_ROLE).to_s
    is_final = fetch_any(data, KEYS_FINAL)
    metadata = symbolize_hash(data)

    event_class = if role == "user"
      Riffer::Voice::Events::InputTranscript
    else
      Riffer::Voice::Events::OutputTranscript
    end

    [event_class.new(
      text: text.to_s,
      is_final: is_final.nil? ? nil : is_final == true,
      metadata: metadata
    )]
  end

  #: (Hash[String, untyped], retriable: bool, ?fallback_code: String?) -> Riffer::Voice::Events::Error
  def parse_error_event(data, retriable:, fallback_code: nil)
    Riffer::Voice::Events::Error.new(
      code: (fetch_any(data, KEYS_ERROR_CODE) || fallback_code || "deepgram_voice_agent_error").to_s,
      message: (fetch_any(data, KEYS_ERROR_MESSAGE) || "Deepgram voice agent error").to_s,
      retriable: retriable,
      metadata: symbolize_hash(data)
    )
  end

  #: (untyped) -> Hash[String, untyped]
  def parse_arguments(arguments)
    return {} if arguments.nil?
    return deep_stringify(arguments) if arguments.is_a?(Hash)

    parsed = JSON.parse(arguments.to_s)
    return deep_stringify(parsed) if parsed.is_a?(Hash)

    warn_invalid_tool_arguments("expected JSON object, got #{parsed.class}")
    {}
  rescue JSON::ParserError => error
    warn_invalid_tool_arguments("json parse failed (#{error.class}: #{error.message})")
    {}
  end

  #: (String) -> void
  def warn_invalid_tool_arguments(reason)
    Warning.warn("[riffer] deepgram parser normalized invalid tool arguments: #{reason}\n")
  end
end
