# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::OpenaiRealtimeLifecycle
  include Riffer::Voice::Drivers::RealtimeLifecycleSupport

  #: (api_key: String?, ?model: String, ?endpoint: String, ?transport_factory: ^(url: String, headers: Hash[String, String]) -> untyped, ?parser: Riffer::Voice::Parsers::OpenAIRealtimeParser, ?task_resolver: ^() -> untyped, ?response_state_lock: untyped, ?logger: untyped) -> void
  def initialize(api_key: nil, model: Riffer::Voice::Drivers::OpenAIRealtime::DEFAULT_MODEL, endpoint: Riffer::Voice::Drivers::OpenAIRealtime::DEFAULT_ENDPOINT, transport_factory: nil, parser: Riffer::Voice::Parsers::OpenAIRealtimeParser.new, task_resolver: nil, response_state_lock: nil, logger: nil)
    super(model: model, logger: logger)
    @api_key = api_key || Riffer.config.openai.api_key
    @endpoint = endpoint
    @transport_factory = transport_factory || default_transport_factory
    @parser = parser
    @task_resolver = task_resolver || default_task_resolver
    @transport = nil
    @reader_task = nil
    @response_state_lock = response_state_lock || Riffer::Voice::Drivers::OpenAIRealtime::NoopResponseStateLock.new
    @output_voice = Riffer::Voice::Drivers::OpenAIRealtime::DEFAULT_OUTPUT_VOICE
    @response_in_progress = false
    @response_create_pending = false
    @response_create_in_flight = false
  end

  #: (system_prompt: String, ?tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]], ?config: Hash[Symbol | String, untyped], ?callbacks: Hash[Symbol, ^(Riffer::Voice::Events::Base) -> void]) -> bool
  def connect(system_prompt:, tools: [], config: {}, callbacks: {})
    connect_realtime!(
      already_connected_message: "OpenAI realtime connection already open",
      callbacks: callbacks,
      connect_error_code: "openai_realtime_connect_failed",
      reader_annotation: "riffer-voice-openai-realtime-reader"
    ) do
      setup_openai_transport(system_prompt: system_prompt, tools: tools, config: config)
    end
  end

  #: (?reason: String?) -> void
  def close(reason: nil)
    close_realtime!(close_error_code: "openai_realtime_close_failed", reason: reason) do
      with_response_state_lock { reset_response_tracking! }
    end
  end

  private

  #: (system_prompt: String, tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]], config: Hash[Symbol | String, untyped]) -> void
  def setup_openai_transport(system_prompt:, tools:, config:)
    @transport = @transport_factory.call(url: websocket_url, headers: websocket_headers)
    @transport.write_json(build_session_update_payload(system_prompt: system_prompt, tools: tools, config: config))
  end
end
