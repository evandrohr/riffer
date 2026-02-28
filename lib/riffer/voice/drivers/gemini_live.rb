# frozen_string_literal: true
# rbs_inline: enabled

require "cgi"
require "json"

# Gemini Live realtime voice driver.
class Riffer::Voice::Drivers::GeminiLive < Riffer::Voice::Drivers::Base
  include Riffer::Voice::Drivers::RuntimeSupport
  include Riffer::Voice::Drivers::GeminiLiveLifecycle
  include Riffer::Voice::Drivers::GeminiLiveDispatch
  include Riffer::Voice::Drivers::GeminiLiveConnection
  include Riffer::Voice::Drivers::GeminiLivePayloads

  DEFAULT_ENDPOINT = [
    "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.",
    "GenerativeService.BidiGenerateContent"
  ].join #: String

  DEFAULT_AUDIO_MIME_TYPE = "audio/pcm;rate=16000" #: String
  DEFAULT_MODEL = "gemini-2.5-flash-native-audio-preview-12-2025" #: String
  DEFAULT_RESPONSE_MODALITIES = ["AUDIO"].freeze #: Array[String]
  UNSUPPORTED_SCHEMA_KEYS = ["additionalProperties"].freeze #: Array[String]
end
