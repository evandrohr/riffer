# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::GeminiLiveLifecycle
  include Riffer::Voice::Drivers::RealtimeLifecycleSupport

  #: (api_key: String?, ?model: String, ?endpoint: String, ?transport_factory: ^(url: String, headers: Hash[String, String]) -> untyped, ?parser: Riffer::Voice::Parsers::GeminiLiveParser, ?task_resolver: ^() -> untyped, ?logger: untyped) -> void
  def initialize(api_key: nil, model: Riffer::Voice::Drivers::GeminiLive::DEFAULT_MODEL, endpoint: Riffer::Voice::Drivers::GeminiLive::DEFAULT_ENDPOINT, transport_factory: nil, parser: Riffer::Voice::Parsers::GeminiLiveParser.new, task_resolver: nil, logger: nil)
    super(model: model, logger: logger)
    @api_key = api_key || Riffer.config.gemini.api_key
    @endpoint = endpoint
    @transport_factory = transport_factory || default_transport_factory
    @parser = parser
    @task_resolver = task_resolver || default_task_resolver
    @transport = nil
    @reader_task = nil
  end

  #: (system_prompt: String, ?tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]], ?config: Hash[Symbol | String, untyped], ?callbacks: Hash[Symbol, ^(Riffer::Voice::Events::Base) -> void]) -> bool
  def connect(system_prompt:, tools: [], config: {}, callbacks: {})
    connect_realtime!(
      already_connected_message: "Gemini realtime connection already open",
      callbacks: callbacks,
      connect_error_code: "gemini_connect_failed",
      reader_annotation: "riffer-voice-gemini-reader"
    ) do
      setup_gemini_transport(system_prompt: system_prompt, tools: tools, config: config)
    end
  end

  #: (?reason: String?) -> void
  def close(reason: nil)
    close_realtime!(close_error_code: "gemini_close_failed", reason: reason)
  end

  private

  #: (system_prompt: String, tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]], config: Hash[Symbol | String, untyped]) -> void
  def setup_gemini_transport(system_prompt:, tools:, config:)
    @transport = @transport_factory.call(url: websocket_url, headers: {})
    @transport.write_json(build_setup_payload(system_prompt: system_prompt, tools: tools, config: config))
  end
end
