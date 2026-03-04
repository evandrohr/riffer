# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::DeepgramVoiceAgentLifecycle
  include Riffer::Voice::Drivers::RealtimeLifecycleSupport

  #: (api_key: String?, ?model: String, ?endpoint: String, ?transport_factory: ^(url: String, headers: Hash[String, String]) -> untyped, ?parser: Riffer::Voice::Parsers::DeepgramVoiceAgentParser, ?task_resolver: ^() -> untyped, ?logger: untyped) -> void
  def initialize(api_key: nil, model: Riffer::Voice::Drivers::DeepgramVoiceAgent::DEFAULT_MODEL, endpoint: Riffer::Voice::Drivers::DeepgramVoiceAgent::DEFAULT_ENDPOINT, transport_factory: nil, parser: Riffer::Voice::Parsers::DeepgramVoiceAgentParser.new, task_resolver: nil, logger: nil)
    super(model: model, logger: logger)
    @api_key = api_key || Riffer.config.deepgram.api_key
    @endpoint = endpoint
    @transport_factory = transport_factory || default_transport_factory
    @parser = parser
    @task_resolver = task_resolver || default_task_resolver
    @transport = nil
    @reader_task = nil
    @output_audio_mime_type = Riffer::Voice::Drivers::DeepgramVoiceAgent::DEFAULT_OUTPUT_AUDIO_MIME_TYPE
    reset_tool_response_delivery_state!
  end

  #: (system_prompt: String, ?tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]], ?config: Hash[Symbol | String, untyped], ?callbacks: Hash[Symbol, ^(Riffer::Voice::Events::Base) -> void]) -> bool
  def connect(system_prompt:, tools: [], config: {}, callbacks: {})
    connect_realtime!(
      already_connected_message: "Deepgram voice agent connection already open",
      callbacks: callbacks,
      connect_error_code: "deepgram_voice_agent_connect_failed",
      reader_annotation: "riffer-voice-deepgram-reader"
    ) do
      setup_deepgram_transport(system_prompt: system_prompt, tools: tools, config: config)
    end
  end

  #: (?reason: String?) -> void
  def close(reason: nil)
    close_realtime!(
      close_error_code: "deepgram_voice_agent_close_failed",
      reason: reason
    )
  end

  private

  #: (system_prompt: String, tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]], config: Hash[Symbol | String, untyped]) -> void
  def setup_deepgram_transport(system_prompt:, tools:, config:)
    reset_tool_response_delivery_state!
    @transport = @transport_factory.call(url: websocket_url, headers: websocket_headers)
    settings_payload = build_settings_payload(system_prompt: system_prompt, tools: tools, config: config)
    @output_audio_mime_type = output_audio_mime_type_from_settings(settings_payload)
    @transport.write_json(settings_payload)
    log_deepgram_debug(
      event: "deepgram_voice_agent_settings_sent",
      think_provider: settings_payload.dig("agent", "think", "provider", "type"),
      think_model: settings_payload.dig("agent", "think", "provider", "model"),
      functions_count: Array(settings_payload.dig("agent", "think", "functions")).length,
      output_mime_type: @output_audio_mime_type
    )
  end

  #: () -> void
  def reset_tool_response_delivery_state!
    @agent_speaking = false
    @pending_tool_responses = []
    @last_outbound_message_type = nil
    @last_tool_response_message = nil
  end

  #: () -> bool
  def deepgram_debug_enabled?
    value = ENV.fetch("RIFFER_DEEPGRAM_DEBUG", "").to_s.strip.downcase
    value == "1" || value == "true" || value == "yes" || value == "on"
  end

  #: (event: String, **untyped) -> void
  def log_deepgram_debug(event:, **payload)
    return unless deepgram_debug_enabled?
    return unless @logger&.respond_to?(:info)

    @logger.info(
      {
        type: self.class.name,
        event: event
      }.merge(payload)
    )
  rescue
    nil
  end

  #: (system_prompt: String, tools: Array[singleton(Riffer::Tool) | Hash[Symbol | String, untyped]], config: Hash[Symbol | String, untyped]) -> Hash[String, untyped]
  def build_settings_payload(system_prompt:, tools:, config:)
    base_payload = default_settings_payload(system_prompt: system_prompt, tools: tools)
    merged = deep_merge(base_payload, deep_stringify(config || {}))
    merged["type"] = "Settings"
    merged
  end
end
