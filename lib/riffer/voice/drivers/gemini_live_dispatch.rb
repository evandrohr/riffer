# frozen_string_literal: true
# rbs_inline: enabled

module Riffer::Voice::Drivers::GeminiLiveDispatch
  #: (payload: String, mime_type: String) -> void
  def send_audio_chunk(payload:, mime_type: Riffer::Voice::Drivers::GeminiLive::DEFAULT_AUDIO_MIME_TYPE)
    return if payload.nil? || payload.empty? || !connected?
    with_driver_error_handling(
      error_code: "gemini_send_audio_failed",
      failure_message: "gemini live failed sending audio chunk"
    ) do
      @transport.write_json(
        "realtimeInput" => {
          "audio" => {
            "data" => payload,
            "mimeType" => mime_type
          }
        }
      )
    end
  end

  #: (text: String, ?role: String) -> void
  def send_text_turn(text:, role: "user")
    return if text.nil? || text.empty? || !connected?
    with_driver_error_handling(
      error_code: "gemini_send_text_failed",
      failure_message: "gemini live failed sending text turn"
    ) do
      @transport.write_json(
        "clientContent" => {
          "turns" => [
            {
              "role" => role,
              "parts" => [{"text" => text}]
            }
          ],
          "turnComplete" => true
        }
      )
    end
  end

  #: (call_id: String, result: untyped) -> void
  def send_tool_response(call_id:, result:)
    return if call_id.nil? || call_id.empty? || !connected?
    with_driver_error_handling(
      error_code: "gemini_send_tool_response_failed",
      failure_message: "gemini live failed sending tool response"
    ) do
      response_payload = normalize_tool_response_payload(
        call_id: call_id,
        result: result,
        default_name: consume_pending_tool_call_name(call_id: call_id)
      )
      @transport.write_json(
        "toolResponse" => {
          "functionResponses" => [response_payload]
        }
      )
    end
  end

  private

  #: (call_id: String, name: String) -> void
  def register_pending_tool_call_name(call_id:, name:)
    call_id_value = call_id.to_s
    name_value = name.to_s
    return if call_id_value.empty? || name_value.empty?

    synchronized_pending_tool_call_names do |names|
      names[call_id_value] = name_value
    end
  end

  #: (call_id: String) -> String?
  def consume_pending_tool_call_name(call_id:)
    call_id_value = call_id.to_s
    return nil if call_id_value.empty?

    synchronized_pending_tool_call_names do |names|
      names.delete(call_id_value)
    end
  end

  #: () -> void
  def clear_pending_tool_call_names!
    synchronized_pending_tool_call_names(&:clear)
  end

  #: () { (Hash[String, String]) -> untyped } -> untyped
  def synchronized_pending_tool_call_names
    @pending_tool_call_names_mutex.synchronize do
      yield(@pending_tool_call_names)
    end
  end
end
