# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::OpenaiRealtimeDispatch
  #: (payload: String, mime_type: String) -> void
  def send_audio_chunk(payload:, mime_type: Riffer::Voice::Drivers::OpenAIRealtime::DEFAULT_AUDIO_MIME_TYPE)
    return if payload.nil? || payload.empty? || !connected?
    with_driver_error_handling(
      error_code: "openai_realtime_send_audio_failed",
      failure_message: "openai realtime failed sending audio chunk"
    ) do
      normalized_audio_payload = normalize_input_audio_payload(payload: payload, mime_type: mime_type)
      @transport.write_json(
        "type" => "input_audio_buffer.append",
        "audio" => normalized_audio_payload
      )
    end
  end

  #: (text: String, ?role: String) -> void
  def send_text_turn(text:, role: "user")
    return if text.nil? || text.empty? || !connected?
    with_driver_error_handling(
      error_code: "openai_realtime_send_text_failed",
      failure_message: "openai realtime failed sending text turn"
    ) do
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
    end
  end

  #: (call_id: String, result: untyped) -> void
  def send_tool_response(call_id:, result:)
    return if call_id.nil? || call_id.empty? || !connected?
    with_driver_error_handling(
      error_code: "openai_realtime_send_tool_response_failed",
      failure_message: "openai realtime failed sending tool response"
    ) do
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
    end
  end
end
