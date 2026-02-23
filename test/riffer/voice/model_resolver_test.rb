# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::ModelResolver do
  before do
    @original_openai_api_key = Riffer.config.openai.api_key
    @original_gemini_api_key = Riffer.config.gemini.api_key
  end

  after do
    Riffer.config.openai.api_key = @original_openai_api_key
    Riffer.config.gemini.api_key = @original_gemini_api_key
  end

  it "resolves openai provider/model into adapter identifier and provider model" do
    Riffer.config.openai.api_key = "test-openai-key"

    resolved = Riffer::Voice::ModelResolver.resolve(model: "openai/gpt-realtime")

    expect(resolved).must_equal(
      {
        provider: "openai",
        adapter_identifier: :openai_realtime,
        model: "gpt-realtime"
      }
    )
  end

  it "resolves gemini provider/model into adapter identifier and provider model" do
    Riffer.config.gemini.api_key = "test-gemini-key"

    resolved = Riffer::Voice::ModelResolver.resolve(model: "gemini/gemini-2.5-flash-native-audio-preview-12-2025")

    expect(resolved).must_equal(
      {
        provider: "gemini",
        adapter_identifier: :gemini_live,
        model: "gemini-2.5-flash-native-audio-preview-12-2025"
      }
    )
  end

  it "rejects model strings without provider/model format" do
    expect {
      Riffer::Voice::ModelResolver.resolve(model: "gpt-realtime", validate_config: false)
    }.must_raise Riffer::ArgumentError
  end

  it "rejects legacy model prefixes" do
    expect {
      Riffer::Voice::ModelResolver.resolve(model: "openai_realtime/gpt-realtime", validate_config: false)
    }.must_raise Riffer::ArgumentError
  end

  it "rejects unsupported providers" do
    expect {
      Riffer::Voice::ModelResolver.resolve(model: "anthropic/claude", validate_config: false)
    }.must_raise Riffer::ArgumentError
  end

  it "requires provider api key by default" do
    Riffer.config.openai.api_key = nil

    expect {
      Riffer::Voice::ModelResolver.resolve(model: "openai/gpt-realtime")
    }.must_raise Riffer::ArgumentError
  end

  it "can skip provider api key validation for injected adapter paths" do
    Riffer.config.openai.api_key = nil

    resolved = Riffer::Voice::ModelResolver.resolve(model: "openai/gpt-realtime", validate_config: false)
    expect(resolved[:adapter_identifier]).must_equal :openai_realtime
  end
end
