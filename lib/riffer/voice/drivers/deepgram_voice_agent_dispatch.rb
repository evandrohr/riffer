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
      @transport.write_json(
        "type" => "InjectUserMessage",
        "content" => text,
        "role" => role
      )
    end
  end

  #: (call_id: String, result: untyped) -> void
  def send_tool_response(call_id:, result:)
    return if call_id.nil? || call_id.empty? || !connected?

    with_driver_error_handling(
      error_code: "deepgram_voice_agent_send_tool_response_failed",
      failure_message: "deepgram voice agent failed sending tool response"
    ) do
      @transport.write_json(
        "type" => "FunctionCallResponse",
        "id" => call_id,
        "content" => serialize_tool_result(result)
      )
    end
  end

  private

  #: (untyped) -> String
  def serialize_tool_result(result)
    return result if result.is_a?(String)

    JSON.generate(result)
  end
end
