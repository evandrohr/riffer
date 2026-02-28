# frozen_string_literal: true
# rbs_inline: enabled

# Shared constants for OpenAI realtime payload parsing.
module Riffer::Voice::Parsers::OpenaiRealtimeParserConstants
  DEFAULT_AUDIO_MIME_TYPE = "audio/pcm;rate=24000" #: String
  NON_ERROR_RESPONSE_STATUSES = ["cancelled", "canceled"].freeze #: Array[String]

  INTERRUPT_TYPES = [
    "input_audio_buffer.speech_started",
    "response.interrupted",
    "response.cancelled"
  ].freeze #: Array[String]

  AUDIO_DELTA_TYPES = [
    "response.output_audio.delta",
    "response.audio.delta",
    "response.output_audio.done",
    "response.audio.done"
  ].freeze #: Array[String]

  INPUT_TRANSCRIPT_DELTA_TYPES = ["conversation.item.input_audio_transcription.delta"].freeze #: Array[String]
  INPUT_TRANSCRIPT_FINAL_TYPES = [
    "conversation.item.input_audio_transcription.completed",
    "conversation.item.input_audio_transcription.done"
  ].freeze #: Array[String]

  OUTPUT_TRANSCRIPT_DELTA_TYPES = [
    "response.output_audio_transcript.delta",
    "response.audio_transcript.delta",
    "response.output_text.delta",
    "response.text.delta"
  ].freeze #: Array[String]

  OUTPUT_TRANSCRIPT_FINAL_TYPES = [
    "response.output_audio_transcript.done",
    "response.audio_transcript.done",
    "response.output_text.done",
    "response.text.done"
  ].freeze #: Array[String]

  OUTPUT_ITEM_TYPES = ["response.output_item.added", "response.output_item.done"].freeze #: Array[String]
  CONTENT_PART_DELTA_TYPES = ["response.content_part.added"].freeze #: Array[String]
  CONTENT_PART_FINAL_TYPES = ["response.content_part.done"].freeze #: Array[String]

  KEYS_DELTA_PAYLOAD = ["delta", "audio", "data"].freeze #: Array[String]
  KEYS_PART_AUDIO = ["audio", "delta", "data"].freeze #: Array[String]
  KEYS_MIME_TYPE = ["mime_type", "mimeType"].freeze #: Array[String]
  KEYS_DELTA_TEXT = ["delta", "transcript", "text"].freeze #: Array[String]
  KEYS_TRANSCRIPT_TEXT = ["transcript", "text"].freeze #: Array[String]
  KEYS_CALL_ID = ["call_id", "callId", "item_id", "itemId"].freeze #: Array[String]
  KEYS_ITEM_ID = ["item_id", "itemId"].freeze #: Array[String]
  KEYS_ERROR_CODE = ["code", "type"].freeze #: Array[String]
  KEYS_INPUT_TOKENS = ["input_tokens", "inputTokens"].freeze #: Array[String]
  KEYS_OUTPUT_TOKENS = ["output_tokens", "outputTokens"].freeze #: Array[String]
  KEYS_INPUT_AUDIO_TOKENS = ["input_audio_tokens", "inputAudioTokens"].freeze #: Array[String]
  KEYS_OUTPUT_AUDIO_TOKENS = ["output_audio_tokens", "outputAudioTokens"].freeze #: Array[String]
  KEYS_STATUS_DETAILS_CODE = ["code", "type"].freeze #: Array[String]

  AUDIO_PART_TYPES = ["audio", "output_audio"].freeze #: Array[String]
  TRANSCRIPT_PART_TYPES = ["audio", "output_audio", "text", "output_text"].freeze #: Array[String]

  RETRIABLE_ERROR_CODES = ["server_error", "rate_limit_exceeded", "overloaded_error"].freeze #: Array[String]
end
