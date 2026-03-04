# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::DeepgramVoiceAgentConnection
  private

  #: () -> void
  def validate_configuration!
    raise Riffer::ArgumentError, "deepgram api_key is required" if @api_key.nil? || @api_key.empty?
    raise Riffer::ArgumentError, "deepgram model is required" if model.nil? || model.empty?
  end

  #: () -> String
  def websocket_url
    @endpoint
  end

  #: () -> Hash[String, String]
  def websocket_headers
    {
      "Authorization" => "#{Riffer::Voice::Drivers::DeepgramVoiceAgent::DEFAULT_AUTH_SCHEME} #{@api_key}"
    }
  end

  #: () -> void
  def read_loop
    while connected?
      transport = @transport
      break if transport.nil?

      frame = transport.read
      break if frame.nil?

      raw_payload = extract_frame_payload(frame)
      next if raw_payload.nil? || raw_payload.to_s.empty?

      if json_frame_payload?(raw_payload)
        payload = parse_frame_payload(raw_payload)
        next unless payload

        handle_server_payload(payload)
        parsed_events = @parser.call(payload)
        log_inbound_payload(payload: payload, parsed_events: parsed_events)
        parsed_events.each { |event| emit_event(event) }
      else
        emit_binary_audio_chunk(raw_payload)
      end
    end
  rescue => error
    emit_error(
      code: "deepgram_voice_agent_reader_failed",
      message: error.message,
      retriable: true,
      metadata: {error_class: error.class.name}
    )
  ensure
    mark_disconnected!
  end

  #: (String) -> Hash[String, untyped]?
  def parse_frame_payload(raw_payload)
    JSON.parse(raw_payload)
  rescue JSON::ParserError => error
    emit_error(
      code: "deepgram_voice_agent_invalid_json",
      message: error.message,
      retriable: true,
      metadata: {payload: raw_payload}
    )
    nil
  end

  #: () -> void
  def stop_reader_task
    stop_async_task(@reader_task)
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

  #: (Hash[String, untyped]) -> void
  def handle_server_payload(payload)
    type = payload["type"].to_s
    previous_speaking = @agent_speaking == true

    case type
    when "AgentStartedSpeaking", "agent_started_speaking"
      @agent_speaking = true
    when "AgentAudioDone", "agent_audio_done", "UserStartedSpeaking", "user_started_speaking"
      @agent_speaking = false
    when "InjectionRefused", "injection_refused"
      requeue_last_tool_response(payload)
    end

    flush_pending_tool_responses_with_recovery unless @agent_speaking
    log_deepgram_debug(
      event: "deepgram_voice_agent_server_state",
      payload_type: type,
      speaking_before: previous_speaking,
      speaking_after: @agent_speaking == true,
      queued_count: Array(@pending_tool_responses).length
    )
  end

  #: () -> void
  def flush_pending_tool_responses_with_recovery
    flush_pending_tool_responses!
  rescue => error
    emit_error(
      code: "deepgram_voice_agent_send_tool_response_failed",
      message: error.message,
      retriable: true,
      metadata: {error_class: error.class.name}
    )
  end

  #: (Hash[String, untyped]) -> void
  def requeue_last_tool_response(payload)
    return unless @last_outbound_message_type == "FunctionCallResponse"
    return unless @last_tool_response_message.is_a?(Hash)

    queue_tool_response_message(@last_tool_response_message)
    @agent_speaking = true if injection_refused_due_to_speaking?(payload)
    log_deepgram_debug(
      event: "deepgram_voice_agent_tool_response_requeued",
      call_id: @last_tool_response_message["id"],
      injection_message: payload["message"],
      queued_count: Array(@pending_tool_responses).length
    )
  end

  #: (Hash[String, untyped]) -> bool
  def injection_refused_due_to_speaking?(payload)
    message = [payload["message"], payload["description"]].compact.join(" ").downcase
    message.include?("speaking")
  end

  #: (String) -> void
  def emit_binary_audio_chunk(raw_payload)
    log_deepgram_debug(
      event: "deepgram_voice_agent_inbound_audio",
      bytes: raw_payload.bytesize
    )
    emit_event(
      Riffer::Voice::Events::AudioChunk.new(
        payload: Base64.strict_encode64(raw_payload.b),
        mime_type: @output_audio_mime_type
      )
    )
  end

  #: (String) -> bool
  def json_frame_payload?(raw_payload)
    utf8_payload = begin
      raw_payload.dup.force_encoding(Encoding::UTF_8)
    rescue
      return false
    end
    return false unless utf8_payload.valid_encoding?

    first_non_space = utf8_payload.lstrip[0]
    first_non_space == "{" || first_non_space == "["
  end

  #: (payload: Hash[String, untyped], parsed_events: Array[Riffer::Voice::Events::Base]) -> void
  def log_inbound_payload(payload:, parsed_events:)
    payload_type = payload["type"].to_s
    log_deepgram_debug(
      event: "deepgram_voice_agent_inbound_message",
      payload_type: payload_type,
      payload_keys: payload.keys,
      parsed_events_count: parsed_events.length,
      parsed_event_types: parsed_events.map { |event| event.class.name },
      call_id: payload["id"] || payload["call_id"] || payload["callId"],
      name: payload["name"] || payload["function_name"] || payload["functionName"]
    )
  end
end
