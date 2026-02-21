# frozen_string_literal: true
# rbs_inline: enabled

# Registry for realtime voice drivers.
class Riffer::Voice::Drivers::Repository
  REPO = {
    gemini_live: -> { Riffer::Voice::Drivers::GeminiLive },
    openai_realtime: -> { Riffer::Voice::Drivers::OpenAIRealtime }
  }.freeze #: Hash[Symbol, ^() -> singleton(Riffer::Voice::Drivers::Base)]

  #: ((String | Symbol)) -> singleton(Riffer::Voice::Drivers::Base)?
  def self.find(identifier)
    REPO.fetch(identifier.to_sym, nil)&.call
  end
end
