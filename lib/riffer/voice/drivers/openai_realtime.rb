# frozen_string_literal: true
# rbs_inline: enabled

require "cgi"
require "json"

# OpenAI Realtime GA voice driver.
class Riffer::Voice::Drivers::OpenAIRealtime < Riffer::Voice::Drivers::Base
  DEFAULT_ENDPOINT = "wss://api.openai.com/v1/realtime" #: String

  DEFAULT_MODEL = "gpt-realtime" #: String

  DEFAULT_INPUT_AUDIO_FORMAT = "pcm16" #: String

  DEFAULT_OUTPUT_AUDIO_FORMAT = "pcm16" #: String

  #: (api_key: String?, ?model: String, ?endpoint: String, ?transport_factory: ^(url: String, headers: Hash[String, String]) -> untyped, ?parser: Riffer::Voice::Parsers::OpenAIRealtimeParser, ?task_resolver: ^() -> untyped, ?logger: untyped) -> void
  def initialize(api_key: nil, model: DEFAULT_MODEL, endpoint: DEFAULT_ENDPOINT, transport_factory: nil, parser: Riffer::Voice::Parsers::OpenAIRealtimeParser.new, task_resolver: nil, logger: nil)
    super(model: model, logger: logger)
    @api_key = api_key || Riffer.config.openai.api_key
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
    raise Riffer::Error, "OpenAI realtime connection already open" if connected?

    reset_callbacks(callbacks)
    validate_configuration!
    task = ensure_async_task!(@task_resolver.call)

    @transport = @transport_factory.call(url: websocket_url, headers: websocket_headers)
    @transport.write_json(build_session_update_payload(system_prompt: system_prompt, tools: tools, config: config))

    mark_connected!
    @reader_task = task.async(annotation: "riffer-voice-openai-realtime-reader") { read_loop }
    true
  rescue Riffer::ArgumentError
    raise
  rescue => error
    cleanup_connection
    emit_error(
      code: "openai_realtime_connect_failed",
      message: error.message,
      retriable: true,
      metadata: {error_class: error.class.name}
    )
    false
  end

  #: (payload: String, mime_type: String) -> void
  def send_audio_chunk(payload:, mime_type: "audio/pcm")
    return if payload.nil? || payload.empty? || !connected?

    @transport.write_json(
      "type" => "input_audio_buffer.append",
      "audio" => payload,
      "mime_type" => mime_type
    )
  rescue => error
    emit_error(code: "openai_realtime_send_audio_failed", message: error.message, retriable: true, metadata: {error_class: error.class.name})
  end

  #: (text: String, ?role: String) -> void
  def send_text_turn(text:, role: "user")
    return if text.nil? || text.empty? || !connected?

    @transport.write_json(
      "type" => "conversation.item.create",
      "item" => {
        "type" => "message",
        "role" => role,
        "content" => [
          {
            "type" => "input_text",
            "text" => text
          }
        ]
      }
    )
  rescue => error
    emit_error(code: "openai_realtime_send_text_failed", message: error.message, retriable: true, metadata: {error_class: error.class.name})
  end

  #: (call_id: String, result: untyped) -> void
  def send_tool_response(call_id:, result:)
    return if call_id.nil? || call_id.empty? || !connected?

    output = result.is_a?(String) ? result : result.to_json

    @transport.write_json(
      "type" => "conversation.item.create",
      "item" => {
        "type" => "function_call_output",
        "call_id" => call_id,
        "output" => output
      }
    )

    @transport.write_json("type" => "response.create")
  rescue => error
    emit_error(code: "openai_realtime_send_tool_response_failed", message: error.message, retriable: true, metadata: {error_class: error.class.name})
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
    emit_error(code: "openai_realtime_close_failed", message: error.message, retriable: false, metadata: {error_class: error.class.name})
  end

  private

  #: () -> void
  def validate_configuration!
    raise Riffer::ArgumentError, "openai api_key is required" if @api_key.nil? || @api_key.empty?
    raise Riffer::ArgumentError, "openai realtime model is required" if model.nil? || model.empty?
  end

  #: () -> String
  def websocket_url
    "#{@endpoint}?model=#{CGI.escape(model)}"
  end

  #: () -> Hash[String, String]
  def websocket_headers
    {
      "Authorization" => "Bearer #{@api_key}"
    }
  end

  #: (system_prompt: String, tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]], config: Hash[Symbol | String, untyped]) -> Hash[String, untyped]
  def build_session_update_payload(system_prompt:, tools:, config:)
    session = {
      "instructions" => system_prompt,
      "input_audio_format" => DEFAULT_INPUT_AUDIO_FORMAT,
      "output_audio_format" => DEFAULT_OUTPUT_AUDIO_FORMAT
    }

    normalized_tools = normalize_openai_tools(tools)
    session["tools"] = normalized_tools unless normalized_tools.empty?

    session.merge!(stringify_hash(config)) unless config.empty?

    {
      "type" => "session.update",
      "session" => session
    }
  end

  #: (Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]]) -> Array[Hash[String, untyped]]
  def normalize_openai_tools(tools)
    tools.filter_map do |tool|
      if tool.is_a?(Class) && tool <= Riffer::Tool
        {
          "type" => "function",
          "name" => tool.name,
          "description" => tool.description,
          "parameters" => tool.parameters_schema,
          "strict" => true
        }
      elsif tool.is_a?(Hash)
        stringify_hash(tool)
      end
    end
  end

  #: () -> void
  def read_loop
    while connected?
      frame = @transport&.read
      break if frame.nil?

      payload = parse_frame_payload(frame)
      next unless payload

      @parser.call(payload).each { |event| emit_event(event) }
    end
  rescue => error
    emit_error(code: "openai_realtime_reader_failed", message: error.message, retriable: true, metadata: {error_class: error.class.name})
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
    emit_error(code: "openai_realtime_invalid_json", message: error.message, retriable: true, metadata: {payload: raw_payload.to_s})
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
