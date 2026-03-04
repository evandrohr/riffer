# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::Drivers::Repository do
  describe ".find" do
    it "returns DeepgramVoiceAgent for :deepgram_voice_agent" do
      expect(Riffer::Voice::Drivers::Repository.find(:deepgram_voice_agent)).must_equal(
        Riffer::Voice::Drivers::DeepgramVoiceAgent
      )
    end

    it "returns GeminiLive for :gemini_live" do
      expect(Riffer::Voice::Drivers::Repository.find(:gemini_live)).must_equal Riffer::Voice::Drivers::GeminiLive
    end

    it "returns OpenAIRealtime for :openai_realtime" do
      expect(Riffer::Voice::Drivers::Repository.find(:openai_realtime)).must_equal Riffer::Voice::Drivers::OpenAIRealtime
    end

    it "returns nil for unknown identifier" do
      expect(Riffer::Voice::Drivers::Repository.find(:unknown)).must_be_nil
    end
  end
end
