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

  it "rejects invalid tools entries with indexed error messages" do
    error = expect {
      Riffer::Voice.connect(
        model: "openai/gpt-realtime",
        system_prompt: "You are helpful",
        tools: [Class.new, "bad-tool-entry"],
        adapter_factory: ->(**_kwargs) { TestSupport::Voice::FakeAdapter.new }
      )
    }.must_raise Riffer::ArgumentError

    expect(error.message).must_include "tools[0]"
  end

  it "rejects invalid tools schema hashes" do
    error = expect {
      Riffer::Voice.connect(
        model: "openai/gpt-realtime",
        system_prompt: "You are helpful",
        tools: [{"name" => "missing_parameters"}],
        adapter_factory: ->(**_kwargs) { TestSupport::Voice::FakeAdapter.new }
      )
    }.must_raise Riffer::ArgumentError

    expect(error.message).must_include "tools[0]"
  end

  it "accepts valid OpenAI-style and Gemini-style tool schema hashes" do
    openai_tool = {
      "type" => "function",
      "name" => "lookup_patient",
      "parameters" => {
        "type" => "object",
        "properties" => {
          "id" => {"type" => "string"}
        }
      }
    }
    gemini_tool = {
      "functionDeclarations" => [
        {
          "name" => "lookup_patient",
          "parameters" => {
            "type" => "object",
            "properties" => {
              "id" => {"type" => "string"}
            }
          }
        }
      ]
    }
    adapter = TestSupport::Voice::FakeAdapter.new

    session = Riffer::Voice.connect(
      model: "openai/gpt-realtime",
      system_prompt: "You are helpful",
      tools: [openai_tool, gemini_tool],
      adapter_factory: ->(**_kwargs) { adapter }
    )

    expect(session).must_be :connected?
    session.close
  end

  it "preserves original connection failure when runtime shutdown also fails" do
    runtime_executor = Object.new
    def runtime_executor.shutdown
      raise "shutdown failed"
    end

    original_error = Riffer::Error.new("model resolution failed")
    resolver_class = Riffer::Voice::Runtime::Resolver
    model_resolver_class = Riffer::Voice::ModelResolver

    raised_error = nil
    _output, error_output = capture_io do
      raised_error = with_overridden_class_method(
        klass: resolver_class,
        method_name: :resolve,
        implementation: ->(requested_mode:, task_resolver: nil) { runtime_executor }
      ) do
        with_overridden_class_method(
          klass: model_resolver_class,
          method_name: :resolve,
          implementation: ->(model:, validate_config:) { raise original_error }
        ) do
          expect {
            Riffer::Voice.connect(
              model: "openai/gpt-realtime",
              system_prompt: "You are helpful"
            )
          }.must_raise Riffer::Error
        end
      end
    end

    expect(raised_error.message).must_equal "model resolution failed"
    expect(error_output).must_include "runtime shutdown failed during voice.connect cleanup"
  end

  private

  def with_overridden_class_method(klass:, method_name:, implementation:)
    singleton = klass.singleton_class
    had_original = singleton.method_defined?(method_name, false) ||
      singleton.private_method_defined?(method_name, false)
    original = singleton.instance_method(method_name) if had_original

    singleton.send(:remove_method, method_name) if had_original
    singleton.send(:define_method, method_name, implementation)
    yield
  ensure
    singleton.send(:remove_method, method_name)
    singleton.send(:define_method, method_name, original) if had_original
  end
end
