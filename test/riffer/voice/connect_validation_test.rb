# frozen_string_literal: true

require "test_helper"
require_relative "../../support/voice/fake_adapter"

describe "Riffer::Voice.connect validation" do
  before do
    @original_openai_api_key = Riffer.config.openai.api_key
    @original_gemini_api_key = Riffer.config.gemini.api_key
  end

  after do
    Riffer.config.openai.api_key = @original_openai_api_key
    Riffer.config.gemini.api_key = @original_gemini_api_key
  end

  it "rejects legacy model prefixes" do
    expect {
      Riffer::Voice.connect(
        model: "openai_realtime/gpt-realtime",
        system_prompt: "You are helpful",
        adapter_factory: ->(**_kwargs) { TestSupport::Voice::FakeAdapter.new }
      )
    }.must_raise Riffer::ArgumentError
  end

  it "requires openai api_key when using built-in openai adapter" do
    Riffer.config.openai.api_key = nil

    expect {
      Riffer::Voice.connect(
        model: "openai/gpt-realtime",
        system_prompt: "You are helpful",
        runtime: :background
      )
    }.must_raise Riffer::ArgumentError
  end

  it "requires gemini api_key when using built-in gemini adapter" do
    Riffer.config.gemini.api_key = nil

    expect {
      Riffer::Voice.connect(
        model: "gemini/gemini-2.5-flash-native-audio-preview-12-2025",
        system_prompt: "You are helpful",
        runtime: :background
      )
    }.must_raise Riffer::ArgumentError
  end

  it "allows adapter injection even when provider api key is not configured" do
    Riffer.config.openai.api_key = nil
    adapter = TestSupport::Voice::FakeAdapter.new

    session = Riffer::Voice.connect(
      model: "openai/gpt-realtime",
      system_prompt: "You are helpful",
      adapter_factory: ->(**_kwargs) { adapter }
    )

    expect(session).must_be :connected?
    session.close
  end
end
