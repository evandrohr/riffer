# frozen_string_literal: true
# rbs_inline: enabled

# Content, audio, and transcript event extraction for OpenAI realtime payloads.
module Riffer::Voice::Parsers::OpenaiRealtimeParserContent
  include Riffer::Voice::Parsers::OpenaiRealtimeParserConstants

  private

  #: (Hash[String, untyped], is_final: bool) -> Array[Riffer::Voice::Events::Base]
  def parse_content_part(data, is_final:)
    part = data["part"]
    return [] unless part.is_a?(Hash)

    parse_message_parts([part], is_final: is_final)
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_audio_delta(data)
    payload = fetch_any(data, KEYS_DELTA_PAYLOAD)
    audio_chunk_event(payload: payload, mime_type: fetch_any(data, KEYS_MIME_TYPE))
  end

  #: (Hash[String, untyped], is_final: bool) -> Array[Riffer::Voice::Events::Base]
  def parse_input_transcript(data, is_final:)
    transcript_event(
      klass: Riffer::Voice::Events::InputTranscript,
      text: fetch_any(data, KEYS_DELTA_TEXT),
      is_final: is_final,
      metadata_source: data
    )
  end

  #: (Hash[String, untyped], is_final: bool) -> Array[Riffer::Voice::Events::Base]
  def parse_output_transcript(data, is_final:)
    transcript_event(
      klass: Riffer::Voice::Events::OutputTranscript,
      text: fetch_any(data, KEYS_DELTA_TEXT),
      is_final: is_final,
      metadata_source: data
    )
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def parse_output_item(data)
    item = data["item"]
    return [] unless item.is_a?(Hash)

    return [] if item["type"].to_s == "function_call"
    return [] unless item["type"].to_s == "message"

    parse_output_item_message(item, is_final: data["type"] == "response.output_item.done")
  end

  #: (Hash[String, untyped], is_final: bool) -> Array[Riffer::Voice::Events::Base]
  def parse_output_item_message(item, is_final:)
    content = item["content"]
    return [] unless content.is_a?(Array)

    parse_message_parts(content, is_final: is_final)
  end

  #: (Array[untyped], is_final: bool) -> Array[Riffer::Voice::Events::Base]
  def parse_message_parts(content_parts, is_final:)
    content_parts.each_with_object([]) do |part, events|
      next unless part.is_a?(Hash)

      events.concat(part_audio_events(part))
      events.concat(part_transcript_events(part, is_final: is_final))
    end
  end

  #: (Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def part_audio_events(part)
    part_type = part["type"].to_s
    return [] unless AUDIO_PART_TYPES.include?(part_type)

    audio_chunk_event(payload: fetch_any(part, KEYS_PART_AUDIO), mime_type: fetch_any(part, KEYS_MIME_TYPE))
  end

  #: (Hash[String, untyped], is_final: bool) -> Array[Riffer::Voice::Events::Base]
  def part_transcript_events(part, is_final:)
    part_type = part["type"].to_s
    return [] unless TRANSCRIPT_PART_TYPES.include?(part_type)

    transcript_event(
      klass: Riffer::Voice::Events::OutputTranscript,
      text: fetch_any(part, KEYS_TRANSCRIPT_TEXT),
      is_final: is_final,
      metadata_source: part
    )
  end

  #: (payload: untyped, mime_type: untyped) -> Array[Riffer::Voice::Events::Base]
  def audio_chunk_event(payload:, mime_type:)
    payload_text = payload.to_s
    return [] if payload_text.empty?

    [Riffer::Voice::Events::AudioChunk.new(
      payload: payload_text,
      mime_type: (mime_type || DEFAULT_AUDIO_MIME_TYPE).to_s
    )]
  end

  #: (klass: singleton(Riffer::Voice::Events::Base), text: untyped, is_final: bool, metadata_source: Hash[String, untyped]) -> Array[Riffer::Voice::Events::Base]
  def transcript_event(klass:, text:, is_final:, metadata_source:)
    text_value = text.to_s
    return [] if text_value.empty?

    [klass.new(
      text: text_value,
      is_final: is_final,
      metadata: symbolize_hash(metadata_source)
    )]
  end
end
