# frozen_string_literal: true
# rbs_inline: enabled

require "cgi"
require "json"

# OpenAI Realtime GA voice driver.
class Riffer::Voice::Drivers::OpenAIRealtime < Riffer::Voice::Drivers::Base
  include Riffer::Voice::Drivers::RuntimeSupport
  include Riffer::Voice::Drivers::OpenaiRealtimeLifecycle
  include Riffer::Voice::Drivers::OpenaiRealtimeDispatch
  include Riffer::Voice::Drivers::OpenaiRealtimeConnection
  include Riffer::Voice::Drivers::OpenaiRealtimeSessionConfig
  include Riffer::Voice::Drivers::OpenaiRealtimeResponseState
  include Riffer::Voice::Drivers::OpenaiRealtimeAudio

  DEFAULT_ENDPOINT = "wss://api.openai.com/v1/realtime" #: String

  DEFAULT_MODEL = "gpt-realtime-1.5" #: String

  DEFAULT_AUDIO_FORMAT_TYPE = "audio/pcm" #: String

  DEFAULT_AUDIO_MIME_TYPE = "audio/pcm" #: String

  DEFAULT_AUDIO_SAMPLE_RATE = 24_000 #: Integer
  SAMPLE_RATE_CACHE_LIMIT = 32 #: Integer

  DEFAULT_INPUT_TRANSCRIPTION_MODEL = "gpt-4o-mini-transcribe" #: String

  DEFAULT_OUTPUT_VOICE = "alloy" #: String

  DEFAULT_OUTPUT_MODALITIES = ["audio"].freeze #: Array[String]

  RESPONSE_CREATE_PAYLOAD = {
    "type" => "response.create",
    "response" => {
      "output_modalities" => DEFAULT_OUTPUT_MODALITIES,
      "audio" => {
        "output" => {
          "voice" => DEFAULT_OUTPUT_VOICE,
          "format" => {
            "type" => DEFAULT_AUDIO_FORMAT_TYPE,
            "rate" => DEFAULT_AUDIO_SAMPLE_RATE
          }.freeze
        }.freeze
      }.freeze
    }.freeze
  }.freeze #: Hash[String, untyped]

  # Lock shim used for async/fiber runtime where cross-thread coordination is not required.
  class NoopResponseStateLock
    #: () { () -> untyped } -> untyped
    def synchronize
      yield
    end
  end
end
