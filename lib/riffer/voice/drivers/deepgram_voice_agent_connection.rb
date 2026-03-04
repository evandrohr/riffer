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

        @parser.call(payload).each { |event| emit_event(event) }
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

  #: (String) -> void
  def emit_binary_audio_chunk(raw_payload)
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
end
