# frozen_string_literal: true
# rbs_inline: enabled

# Registry for internal realtime voice adapters.
class Riffer::Voice::Adapters::Repository
  REPO = {
    deepgram_voice_agent: -> { Riffer::Voice::Adapters::DeepgramVoiceAgent },
    gemini_live: -> { Riffer::Voice::Adapters::GeminiLive },
    openai_realtime: -> { Riffer::Voice::Adapters::OpenAIRealtime }
  }.freeze #: Hash[Symbol, ^() -> singleton(Riffer::Voice::Adapters::Base)]

  #: ((String | Symbol)) -> singleton(Riffer::Voice::Adapters::Base)?
  def self.find(identifier)
    REPO.fetch(identifier.to_sym, nil)&.call
  end
end
