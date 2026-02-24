# frozen_string_literal: true
# rbs_inline: enabled

require "cgi"
require "json"

# Gemini Live realtime voice driver.
class Riffer::Voice::Drivers::GeminiLive < Riffer::Voice::Drivers::Base
  DEFAULT_ENDPOINT = [
    "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.",
    "GenerativeService.BidiGenerateContent"
  ].join #: String

  DEFAULT_AUDIO_MIME_TYPE = "audio/pcm;rate=16000" #: String
  DEFAULT_MODEL = "gemini-2.5-flash-native-audio-preview-12-2025" #: String
  DEFAULT_RESPONSE_MODALITIES = ["AUDIO"].freeze #: Array[String]
  UNSUPPORTED_SCHEMA_KEYS = ["additionalProperties"].freeze #: Array[String]

  #: (api_key: String?, ?model: String, ?endpoint: String, ?transport_factory: ^(url: String, headers: Hash[String, String]) -> untyped, ?parser: Riffer::Voice::Parsers::GeminiLiveParser, ?task_resolver: ^() -> untyped, ?logger: untyped) -> void
  def initialize(api_key: nil, model: DEFAULT_MODEL, endpoint: DEFAULT_ENDPOINT, transport_factory: nil, parser: Riffer::Voice::Parsers::GeminiLiveParser.new, task_resolver: nil, logger: nil)
    super(model: model, logger: logger)
    @api_key = api_key || Riffer.config.gemini.api_key
    @endpoint = endpoint
    @transport_factory = transport_factory || ->(url:, headers:) { Riffer::Voice::Transports::AsyncWebsocket.connect(url: url, headers: headers) }
    @parser = parser
    @task_resolver = task_resolver || -> {
      begin
        Async::Task.current
      rescue NameError, RuntimeError
        nil
      end
    }
    @transport = nil
    @reader_task = nil
  end

  #: (system_prompt: String, ?tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]], ?config: Hash[Symbol | String, untyped], ?callbacks: Hash[Symbol, ^(Riffer::Voice::Events::Base) -> void]) -> bool
  def connect(system_prompt:, tools: [], config: {}, callbacks: {})
    raise Riffer::Error, "Gemini realtime connection already open" if connected?

    reset_callbacks(callbacks)
    validate_configuration!
    task = ensure_async_task!(@task_resolver.call)

    @transport = @transport_factory.call(url: websocket_url, headers: {})
    @transport.write_json(build_setup_payload(system_prompt: system_prompt, tools: tools, config: config))

    mark_connected!
    @reader_task = task.async(annotation: "riffer-voice-gemini-reader") { read_loop }
    true
  rescue Riffer::ArgumentError
    raise
  rescue => error
    cleanup_connection
    emit_error(
      code: "gemini_connect_failed",
      message: error.message,
      retriable: true,
      metadata: {error_class: error.class.name}
    )
    false
  end

  #: (payload: String, mime_type: String) -> void
  def send_audio_chunk(payload:, mime_type: DEFAULT_AUDIO_MIME_TYPE)
    return if payload.nil? || payload.empty? || !connected?

    @transport.write_json(
      "realtimeInput" => {
        "audio" => {
          "data" => payload,
          "mimeType" => mime_type
        }
      }
    )
  rescue => error
    emit_error(code: "gemini_send_audio_failed", message: error.message, retriable: true, metadata: {error_class: error.class.name})
  end

  #: (text: String, ?role: String) -> void
  def send_text_turn(text:, role: "user")
    return if text.nil? || text.empty? || !connected?

    @transport.write_json(
      "clientContent" => {
        "turns" => [
          {
            "role" => role,
            "parts" => [{"text" => text}]
          }
        ],
        "turnComplete" => true
      }
    )
  rescue => error
    emit_error(code: "gemini_send_text_failed", message: error.message, retriable: true, metadata: {error_class: error.class.name})
  end

  #: (call_id: String, result: untyped) -> void
  def send_tool_response(call_id:, result:)
    return if call_id.nil? || call_id.empty? || !connected?

    response_payload = normalize_tool_response_payload(call_id: call_id, result: result)

    @transport.write_json(
      "toolResponse" => {
        "functionResponses" => [response_payload]
      }
    )
  rescue => error
    emit_error(code: "gemini_send_tool_response_failed", message: error.message, retriable: true, metadata: {error_class: error.class.name})
  end

  #: (?reason: String?) -> void
  def close(reason: nil)
    return if closed?

    mark_closed!
    stop_reader_task
    @transport&.close
    @transport = nil
    @reader_task = nil
    log_debug(reason: reason)
  rescue => error
    emit_error(code: "gemini_close_failed", message: error.message, retriable: false, metadata: {error_class: error.class.name})
  end

  private

  #: () -> void
  def validate_configuration!
    raise Riffer::ArgumentError, "gemini api_key is required" if @api_key.nil? || @api_key.empty?
    raise Riffer::ArgumentError, "gemini model is required" if model.nil? || model.empty?
  end

  #: () -> String
  def websocket_url
    # Gemini Live requires API key authentication via query parameter.
    "#{@endpoint}?key=#{CGI.escape(@api_key)}"
  end

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
          "responseModalities" => DEFAULT_RESPONSE_MODALITIES.dup
        }
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
        next if UNSUPPORTED_SCHEMA_KEYS.include?(string_key)

        normalized[string_key] = sanitize_schema(nested_value)
      end
    when Array
      value.map { |item| sanitize_schema(item) }
    else
      value
    end
  end

  #: (call_id: String, result: untyped) -> Hash[String, untyped]
  def normalize_tool_response_payload(call_id:, result:)
    unless result.is_a?(Hash)
      return {
        "id" => call_id,
        "response" => {"result" => result}
      }
    end

    payload = deep_stringify(result)
    tool_payload = {
      "id" => payload["id"].to_s.empty? ? call_id : payload["id"].to_s
    }

    name = payload["name"]
    tool_payload["name"] = name.to_s unless name.nil? || name.to_s.empty?

    response_value = if payload.key?("response")
      payload["response"]
    else
      payload.reject { |key, _value| key == "id" || key == "name" }
    end

    tool_payload["response"] = response_value.is_a?(Hash) ? response_value : {"result" => response_value}
    tool_payload
  end

  #: () -> void
  def read_loop
    while connected?
      transport = @transport
      break if transport.nil?

      frame = transport.read
      break if frame.nil?

      payload = parse_frame_payload(frame)
      next unless payload

      @parser.call(payload).each { |event| emit_event(event) }
    end
  rescue => error
    emit_error(code: "gemini_reader_failed", message: error.message, retriable: true, metadata: {error_class: error.class.name})
  ensure
    mark_disconnected!
  end

  #: (untyped) -> Hash[String, untyped]?
  def parse_frame_payload(frame)
    raw_payload = if frame.respond_to?(:to_str)
      frame.to_str
    elsif frame.respond_to?(:payload)
      frame.payload
    else
      frame.to_s
    end

    return nil if raw_payload.nil? || raw_payload.to_s.empty?

    JSON.parse(raw_payload)
  rescue JSON::ParserError => error
    emit_error(code: "gemini_invalid_json", message: error.message, retriable: true, metadata: {payload: raw_payload.to_s})
    nil
  end

  #: () -> void
  def stop_reader_task
    return if @reader_task.nil?

    @reader_task.stop if @reader_task.respond_to?(:stop)
  rescue
    nil
  end

  #: () -> void
  def cleanup_connection
    stop_reader_task
    @transport&.close
    @transport = nil
    @reader_task = nil
    mark_disconnected!
  rescue
    nil
  end
end
