# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::Adapters::Repository do
  describe ".find" do
    it "returns GeminiLive for :gemini_live" do
      expect(Riffer::Voice::Adapters::Repository.find(:gemini_live)).must_equal Riffer::Voice::Adapters::GeminiLive
    end

    it "returns OpenAIRealtime for :openai_realtime" do
      expect(Riffer::Voice::Adapters::Repository.find(:openai_realtime)).must_equal Riffer::Voice::Adapters::OpenAIRealtime
    end

    it "returns nil for unknown identifier" do
      expect(Riffer::Voice::Adapters::Repository.find(:unknown)).must_be_nil
    end
  end
end
