# frozen_string_literal: true
# rbs_inline: enabled

require "cgi"
require "base64"
require "json"

# OpenAI Realtime GA voice driver.
class Riffer::Voice::Drivers::OpenAIRealtime < Riffer::Voice::Drivers::Base
  DEFAULT_ENDPOINT = "wss://api.openai.com/v1/realtime" #: String

  DEFAULT_MODEL = "gpt-realtime" #: String

  DEFAULT_AUDIO_FORMAT_TYPE = "audio/pcm" #: String

  DEFAULT_AUDIO_MIME_TYPE = "audio/pcm" #: String

  DEFAULT_AUDIO_SAMPLE_RATE = 24_000 #: Integer

  DEFAULT_OUTPUT_VOICE = "alloy" #: String

  DEFAULT_OUTPUT_MODALITIES = ["audio"].freeze #: Array[String]

  RESPONSE_CREATE_PAYLOAD = {
    "type" => "response.create",
    "response" => {
      "output_modalities" => DEFAULT_OUTPUT_MODALITIES,
      "audio" => {
        "output" => {
          "voice" => DEFAULT_OUTPUT_VOICE,
          "format" => {
            "type" => DEFAULT_AUDIO_FORMAT_TYPE,
            "rate" => DEFAULT_AUDIO_SAMPLE_RATE
          }.freeze
        }.freeze
      }.freeze
    }.freeze
  }.freeze #: Hash[String, untyped]

  #: (api_key: String?, ?model: String, ?endpoint: String, ?transport_factory: ^(url: String, headers: Hash[String, String]) -> untyped, ?parser: Riffer::Voice::Parsers::OpenAIRealtimeParser, ?task_resolver: ^() -> untyped, ?response_state_lock: untyped, ?logger: untyped) -> void
  def initialize(api_key: nil, model: DEFAULT_MODEL, endpoint: DEFAULT_ENDPOINT, transport_factory: nil, parser: Riffer::Voice::Parsers::OpenAIRealtimeParser.new, task_resolver: nil, response_state_lock: nil, logger: nil)
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
    @response_state_lock = response_state_lock || NoopResponseStateLock.new
    @response_in_progress = false
    @response_create_pending = false
    @response_create_in_flight = false
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
  def send_audio_chunk(payload:, mime_type: DEFAULT_AUDIO_MIME_TYPE)
    return if payload.nil? || payload.empty? || !connected?
    normalized_audio_payload = normalize_input_audio_payload(payload: payload, mime_type: mime_type)

    @transport.write_json(
      "type" => "input_audio_buffer.append",
      "audio" => normalized_audio_payload
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
    request_response_create
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

    request_response_create
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
    with_response_state_lock { reset_response_tracking! }
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
      "type" => "realtime",
      "model" => model,
      "instructions" => system_prompt,
      "output_modalities" => DEFAULT_OUTPUT_MODALITIES,
      "audio" => {
        "input" => {
          "format" => {
            "type" => DEFAULT_AUDIO_FORMAT_TYPE,
            "rate" => DEFAULT_AUDIO_SAMPLE_RATE
          },
          "turn_detection" => {
            "type" => "semantic_vad",
            "create_response" => true,
            "interrupt_response" => false
          }
        },
        "output" => {
          "voice" => DEFAULT_OUTPUT_VOICE,
          "format" => {
            "type" => DEFAULT_AUDIO_FORMAT_TYPE,
            "rate" => DEFAULT_AUDIO_SAMPLE_RATE
          }
        }
      }
    }

    normalized_tools = normalize_openai_tools(tools)
    session["tools"] = normalized_tools unless normalized_tools.empty?

    session = merge_session_config(session: session, config: config)

    {
      "type" => "session.update",
      "session" => session
    }
  end

  #: (session: Hash[String, untyped], config: Hash[Symbol | String, untyped]) -> Hash[String, untyped]
  def merge_session_config(session:, config:)
    return session if config.empty?

    overrides = deep_stringify(config)
    if overrides.key?("turn_detection")
      overrides = overrides.dup
      turn_detection = overrides.delete("turn_detection")
      overrides["audio"] ||= {}
      overrides["audio"]["input"] ||= {}
      overrides["audio"]["input"]["turn_detection"] ||= turn_detection
    end

    deep_merge(session, overrides)
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

  #: (Hash[String, untyped], Hash[String, untyped]) -> Hash[String, untyped]
  def deep_merge(base, overrides)
    merged = base.dup
    overrides.each do |key, value|
      merged[key] = if merged[key].is_a?(Hash) && value.is_a?(Hash)
        deep_merge(merged[key], value)
      else
        value
      end
    end
    merged
  end

  #: (untyped) -> untyped
  def deep_stringify(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested), result|
        result[key.to_s] = deep_stringify(nested)
      end
    when Array
      value.map { |item| deep_stringify(item) }
    else
      value
    end
  end

  #: () -> Hash[String, untyped]
  def response_create_payload
    RESPONSE_CREATE_PAYLOAD
  end

  #: () -> void
  def read_loop
    while connected?
      frame = @transport&.read
      break if frame.nil?

      payload = parse_frame_payload(frame)
      next unless payload

      update_response_tracking(payload)
      parsed_events = @parser.call(payload)
      log_response_payload(payload: payload, parsed_events: parsed_events)
      log_unparsed_response_payload(payload) if parsed_events.empty?
      parsed_events.each { |event| emit_event(event) }
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
    with_response_state_lock { reset_response_tracking! }
    mark_disconnected!
  rescue
    nil
  end

  #: () -> void
  def request_response_create
    should_send = false
    with_response_state_lock do
      if @response_in_progress
        @response_create_pending = true
      else
        @response_in_progress = true
        @response_create_in_flight = true
        @response_create_pending = false
        should_send = true
      end
    end

    return unless should_send

    @transport.write_json(response_create_payload)
  rescue => error
    with_response_state_lock do
      @response_create_in_flight = false
      @response_in_progress = false
    end
    raise error
  end

  #: (Hash[String, untyped]) -> void
  def update_response_tracking(payload)
    type = payload["type"].to_s
    should_flush = false
    with_response_state_lock do
      case type
      when "response.created", "response.in_progress"
        @response_create_in_flight = false
        @response_in_progress = true
      when "response.done", "response.completed", "response.cancelled", "response.canceled", "response.failed"
        @response_create_in_flight = false
        @response_in_progress = false
        should_flush = @response_create_pending
      when "error"
        should_flush = update_response_tracking_from_error_unlocked(payload)
      end
    end

    flush_pending_response_create if should_flush
  rescue
    nil
  end

  #: (Hash[String, untyped]) -> void
  def update_response_tracking_from_error_unlocked(payload)
    error_payload = payload["error"].is_a?(Hash) ? payload["error"] : {}
    code = (error_payload["code"] || error_payload["type"] || "").to_s
    if code == "conversation_already_has_active_response"
      @response_create_in_flight = false
      @response_in_progress = true
      @response_create_pending = true
      return false
    end

    return false unless @response_create_in_flight

    @response_create_in_flight = false
    @response_in_progress = false
    @response_create_pending
  end

  #: () -> void
  def flush_pending_response_create
    should_send = false
    with_response_state_lock do
      return unless @response_create_pending
      return unless connected?
      return if @response_in_progress

      @response_in_progress = true
      @response_create_in_flight = true
      @response_create_pending = false
      should_send = true
    end

    return unless should_send

    @transport.write_json(response_create_payload)
  rescue => error
    with_response_state_lock do
      @response_in_progress = false
      @response_create_in_flight = false
      @response_create_pending = true if connected?
    end
    emit_error(
      code: "openai_realtime_send_response_create_failed",
      message: error.message,
      retriable: true,
      metadata: {error_class: error.class.name}
    )
  end

  #: (Hash[String, untyped]) -> void
  def log_unparsed_response_payload(payload)
    type = payload["type"].to_s
    return unless type.start_with?("response.")
    return unless @logger&.respond_to?(:debug)

    response = payload["response"].is_a?(Hash) ? payload["response"] : {}
    @logger.debug(
      type: self.class.name,
      event: "openai_realtime_unparsed_payload",
      payload_type: type,
      payload_keys: payload.keys,
      response_status: response["status"],
      response_status_details: response["status_details"]
    )
  rescue
    nil
  end

  #: (payload: Hash[String, untyped], parsed_events: Array[Riffer::Voice::Events::Base]) -> void
  def log_response_payload(payload:, parsed_events:)
    type = payload["type"].to_s
    return unless type.start_with?("response.")
    return unless @logger&.respond_to?(:debug)

    @logger.debug(
      type: self.class.name,
      event: "openai_realtime_response_payload",
      payload_type: type,
      parsed_events_count: parsed_events.length,
      parsed_event_types: parsed_events.map { |event| event.class.name }
    )
  rescue
    nil
  end

  #: () -> void
  def reset_response_tracking!
    @response_in_progress = false
    @response_create_pending = false
    @response_create_in_flight = false
  end

  #: () { () -> untyped } -> untyped
  def with_response_state_lock
    @response_state_lock.synchronize { yield }
  end

  # Lock shim used for async/fiber runtime where cross-thread coordination is not required.
  class NoopResponseStateLock
    #: () { () -> untyped } -> untyped
    def synchronize
      yield
    end
  end

  #: (payload: String, mime_type: String) -> String
  def normalize_input_audio_payload(payload:, mime_type:)
    mime = mime_type.to_s
    return payload unless mime.include?("audio/pcm")

    source_rate = extract_sample_rate(mime)
    return payload if source_rate.nil? || source_rate == DEFAULT_AUDIO_SAMPLE_RATE

    raw = Base64.strict_decode64(payload)
    resampled = resample_pcm16(raw, from_rate: source_rate, to_rate: DEFAULT_AUDIO_SAMPLE_RATE)
    Base64.strict_encode64(resampled)
  rescue
    payload
  end

  #: (String) -> Integer?
  def extract_sample_rate(mime_type)
    @sample_rate_cache ||= {} #: Hash[String, Integer?]
    return @sample_rate_cache[mime_type] if @sample_rate_cache.key?(mime_type)

    match = mime_type.match(/rate=(?<rate>\d+)/i)
    rate = if match
      value = match[:rate].to_i
      value.positive? ? value : nil
    end

    @sample_rate_cache[mime_type] = rate
  end

  #: (String, from_rate: Integer, to_rate: Integer) -> String
  def resample_pcm16(raw_audio, from_rate:, to_rate:)
    source_samples = raw_audio.unpack("s<*")
    return "".b if source_samples.empty?
    return raw_audio if from_rate == to_rate

    sample_count = [(source_samples.length * to_rate.to_f / from_rate).round, 1].max
    source_max_index = source_samples.length - 1
    resampled = Array.new(sample_count) do |index|
      source_index = (index * from_rate.to_f / to_rate).floor
      source_samples[[source_index, source_max_index].min]
    end

    resampled.pack("s<*")
  end
end
