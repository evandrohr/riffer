# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::DeepgramVoiceAgentDispatch
  #: (payload: String, mime_type: String) -> void
  def send_audio_chunk(payload:, mime_type: Riffer::Voice::Drivers::DeepgramVoiceAgent::DEFAULT_INPUT_AUDIO_MIME_TYPE)
    return if payload.nil? || payload.empty? || !connected?

    with_driver_error_handling(
      error_code: "deepgram_voice_agent_send_audio_failed",
      failure_message: "deepgram voice agent failed sending audio chunk"
    ) do
      decoded_payload = Base64.strict_decode64(payload)
      @transport.write_binary(decoded_payload)
    end
  end

  #: (text: String, ?role: String) -> void
  def send_text_turn(text:, role: "user")
    return if text.nil? || text.empty? || !connected?

    with_driver_error_handling(
      error_code: "deepgram_voice_agent_send_text_failed",
      failure_message: "deepgram voice agent failed sending text turn"
    ) do
      message = {
        "type" => "InjectUserMessage",
        "content" => text
      }
      send_json_message(message, outbound_type: "InjectUserMessage")
    end
  end

  #: (call_id: String, result: untyped) -> void
  def send_tool_response(call_id:, result:)
    return if call_id.nil? || call_id.empty? || !connected?

    with_driver_error_handling(
      error_code: "deepgram_voice_agent_send_tool_response_failed",
      failure_message: "deepgram voice agent failed sending tool response"
    ) do
      payload = normalize_tool_response_payload(result)
      message = {
        "type" => "FunctionCallResponse",
        "id" => call_id,
        "name" => payload[:name],
        "content" => serialize_tool_result(payload[:content])
      }.compact
      deliver_tool_response_message(message)
    end
  end

  private

  #: (untyped) -> String
  def serialize_tool_result(result)
    return result if result.is_a?(String)

    JSON.generate(result)
  end

  #: (untyped) -> Hash[Symbol, untyped]
  def normalize_tool_response_payload(result)
    return { name: nil, content: result } unless result.is_a?(Hash)

    payload = deep_stringify(result)
    name = payload["name"]
    content = payload.key?("response") ? payload["response"] : payload

    {
      name: name.is_a?(String) && !name.empty? ? name : nil,
      content: content
    }
  end

  #: (Hash[String, untyped]) -> void
  def deliver_tool_response_message(message)
    send_json_message(message, outbound_type: "FunctionCallResponse")
  end

  #: () -> void
  def flush_pending_tool_responses!
    return if @pending_tool_responses.nil? || @pending_tool_responses.empty? || @agent_speaking || !connected?

    sent_count = 0
    while !@pending_tool_responses.empty? && !@agent_speaking && connected?
      message = @pending_tool_responses.first
      send_json_message(message, outbound_type: "FunctionCallResponse")
      @pending_tool_responses.shift
      sent_count += 1
    end

    log_deepgram_debug(
      event: "deepgram_voice_agent_tool_response_flush",
      flushed_count: sent_count,
      remaining_count: @pending_tool_responses.length
    )
  end

  #: (Hash[String, untyped]) -> void
  def queue_tool_response_message(message)
    @pending_tool_responses ||= []
    message_id = message["id"].to_s
    already_queued = !message_id.empty? && @pending_tool_responses.any? { |queued| queued["id"].to_s == message_id }
    @pending_tool_responses << message unless already_queued
    log_deepgram_debug(
      event: "deepgram_voice_agent_tool_response_queued",
      call_id: message["id"],
      queued_count: @pending_tool_responses.length,
      already_queued: already_queued
    )
  end

  #: (Hash[String, untyped], outbound_type: String) -> void
  def send_json_message(message, outbound_type:)
    @transport.write_json(message)
    track_outbound_message!(message, outbound_type: outbound_type)
    log_deepgram_debug(
      event: "deepgram_voice_agent_outbound_message",
      outbound_type: outbound_type,
      call_id: message["id"],
      name: message["name"],
      content_size: message["content"].to_s.bytesize,
      agent_speaking: @agent_speaking == true,
      queued_count: Array(@pending_tool_responses).length
    )
  end

  #: (Hash[String, untyped], outbound_type: String) -> void
  def track_outbound_message!(message, outbound_type:)
    @last_outbound_message_type = outbound_type
    @last_tool_response_message = message if outbound_type == "FunctionCallResponse"
  end
end
