# frozen_string_literal: true
# rbs_inline: enabled

# Event-type routing for OpenAI realtime payloads.
module Riffer::Voice::Parsers::OpenaiRealtimeParserDispatch
  include Riffer::Voice::Parsers::OpenaiRealtimeParserConstants

  #: (Hash[Symbol | String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def call(payload)
    data = normalize_hash(payload)
    type = data["type"].to_s
    return [] if type.empty?

    dispatch_event(type: type, data: data)
  end

  private

  #: (type: String, data: Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def dispatch_event(type:, data:)
    return parse_audio_delta(data) if AUDIO_DELTA_TYPES.include?(type)
    return parse_input_transcript(data, is_final: false) if INPUT_TRANSCRIPT_DELTA_TYPES.include?(type)
    return parse_input_transcript(data, is_final: true) if INPUT_TRANSCRIPT_FINAL_TYPES.include?(type)
    return parse_output_transcript(data, is_final: false) if OUTPUT_TRANSCRIPT_DELTA_TYPES.include?(type)
    return parse_output_transcript(data, is_final: true) if OUTPUT_TRANSCRIPT_FINAL_TYPES.include?(type)
    return parse_content_part(data, is_final: false) if CONTENT_PART_DELTA_TYPES.include?(type)
    return parse_content_part(data, is_final: true) if CONTENT_PART_FINAL_TYPES.include?(type)
    return parse_tool_call(data) if type == "response.function_call_arguments.done"
    return parse_output_item(data) if OUTPUT_ITEM_TYPES.include?(type)
    return parse_response_done(data) if type == "response.done"
    return parse_error(data) if type == "error"

    parse_interrupt(type: type)
  end
end
