# frozen_string_literal: true

require "test_helper"
require_relative "../../support/voice/fake_adapter"

module TestSupport
  module Voice
    class EchoTool < Riffer::Tool
      identifier "echo_tool"
      description "Echoes incoming text"

      params do
        required :text, String
      end

      #: (context: Hash[Symbol, untyped]?, text: String) -> Riffer::Tools::Response
      def call(context:, text:)
        prefix = context&.dig(:prefix) || "echo"
        text("#{prefix}: #{text}")
      end
    end

    class RequiredCityTool < Riffer::Tool
      identifier "required_city_tool"
      description "Requires a city argument"

      params do
        required :city, String
      end

      #: (context: Hash[Symbol, untyped]?, city: String) -> Riffer::Tools::Response
      def call(context:, city:)
        text("city=#{city}")
      end
    end

    class SupportVoiceAgent < Riffer::Voice::Agent
      model VoiceModels::OPENAI_PROVIDER_MODEL
      instructions "You are helpful"
      uses_tools [EchoTool]
    end

    class ConfiguredVoiceAgent < Riffer::Voice::Agent
      model VoiceModels::OPENAI_PROVIDER_MODEL
      instructions "Configured"
      uses_tools [EchoTool]
      runtime :background
      voice_config({
        "temperature" => 0.4,
        "audio" => {
          "input" => {
            "turn_detection" => {
              "type" => "semantic_vad"
            }
          }
        }
      })
      auto_handle_tool_calls false
    end
  end
end

describe Riffer::Voice::Agent do
  let(:adapter) { TestSupport::Voice::FakeAdapter.new }
  let(:agent) { TestSupport::Voice::SupportVoiceAgent.new(tool_context: {prefix: "voice"}) }

  before do
    agent.connect(runtime: :background, adapter_factory: ->(**_kwargs) { adapter })
  end

  after do
    agent.close unless agent.closed?
  end

  it "auto-executes tool calls when reading events with next_event" do
    tool_event = Riffer::Voice::Events::ToolCall.new(
      call_id: "call-1",
      name: TestSupport::Voice::EchoTool.name,
      arguments: {"text" => "hello"}
    )
    adapter.emit(tool_event)

    received = agent.next_event(timeout: 0)

    expect(received).must_equal tool_event
    expect(adapter.tool_responses).must_equal([{call_id: "call-1", result: "voice: hello"}])
  end

  it "sends structured unknown_tool errors when tool is not registered" do
    tool_event = Riffer::Voice::Events::ToolCall.new(
      call_id: "call-2",
      name: "missing_tool",
      arguments: {}
    )
    adapter.emit(tool_event)

    agent.next_event(timeout: 0)

    payload = adapter.tool_responses.first[:result]
    expect(payload).must_be_instance_of Hash
    expect(payload.dig("error", "type")).must_equal "unknown_tool"
    expect(payload.dig("error", "message")).must_equal "Unknown tool 'missing_tool'"
  end

  it "serializes validation failures from tools" do
    validation_agent = Riffer::Voice::Agent.new
    validation_adapter = TestSupport::Voice::FakeAdapter.new
    validation_agent.connect(
      model: TestSupport::VoiceModels::OPENAI_PROVIDER_MODEL,
      system_prompt: "You are helpful",
      tools: [TestSupport::Voice::RequiredCityTool],
      runtime: :background,
      adapter_factory: ->(**_kwargs) { validation_adapter }
    )
    validation_event = Riffer::Voice::Events::ToolCall.new(
      call_id: "call-3",
      name: TestSupport::Voice::RequiredCityTool.name,
      arguments: {}
    )
    validation_adapter.emit(validation_event)

    validation_agent.next_event(timeout: 0)

    payload = validation_adapter.tool_responses.first[:result]
    expect(payload).must_be_instance_of Hash
    expect(payload.dig("error", "type")).must_equal "validation_error"
    expect(payload.dig("error", "message")).must_include "city is required"
  ensure
    validation_agent.close unless validation_agent.closed?
  end

  it "can disable auto tool handling per event read" do
    tool_event = Riffer::Voice::Events::ToolCall.new(
      call_id: "call-4",
      name: TestSupport::Voice::EchoTool.name,
      arguments: {"text" => "hello"}
    )
    adapter.emit(tool_event)

    received = agent.next_event(timeout: 0, auto_handle_tool_calls: false)

    expect(received).must_equal tool_event
    expect(adapter.tool_responses).must_equal []
  end

  it "executes tool calls while iterating through events enumerator" do
    tool_event = Riffer::Voice::Events::ToolCall.new(
      call_id: "call-5",
      name: TestSupport::Voice::EchoTool.name,
      arguments: {"text" => "stream"}
    )
    done_event = Riffer::Voice::Events::TurnComplete.new
    adapter.emit(tool_event)
    adapter.emit(done_event)

    received = []
    agent.events.each do |event|
      received << event
      break if event == done_event
    end

    expect(received).must_equal [tool_event, done_event]
    expect(adapter.tool_responses).must_equal([{call_id: "call-5", result: "voice: stream"}])
  end

  it "uses class-level runtime and config defaults when connect does not override" do
    configured_adapter = TestSupport::Voice::FakeAdapter.new
    configured_agent = TestSupport::Voice::ConfiguredVoiceAgent.new
    configured_agent.connect(adapter_factory: ->(**_kwargs) { configured_adapter })

    expect(configured_agent.session.runtime).must_equal :background
    connect_call = configured_adapter.connect_calls.first
    expect(connect_call[:config]).must_equal({
      "temperature" => 0.4,
      "audio" => {
        "input" => {
          "turn_detection" => {
            "type" => "semantic_vad"
          }
        }
      }
    })
  ensure
    configured_agent.close unless configured_agent.nil? || configured_agent.closed?
  end

  it "merges connect config overrides on top of class voice_config" do
    configured_adapter = TestSupport::Voice::FakeAdapter.new
    configured_agent = TestSupport::Voice::ConfiguredVoiceAgent.new
    configured_agent.connect(
      config: {
        "audio" => {
          "input" => {
            "turn_detection" => {
              "create_response" => false
            }
          }
        }
      },
      adapter_factory: ->(**_kwargs) { configured_adapter }
    )

    connect_call = configured_adapter.connect_calls.first
    expect(connect_call[:config]).must_equal({
      "temperature" => 0.4,
      "audio" => {
        "input" => {
          "turn_detection" => {
            "type" => "semantic_vad",
            "create_response" => false
          }
        }
      }
    })
  ensure
    configured_agent.close unless configured_agent.nil? || configured_agent.closed?
  end

  it "prefers explicit runtime override over class runtime default" do
    configured_adapter = TestSupport::Voice::FakeAdapter.new
    configured_agent = TestSupport::Voice::ConfiguredVoiceAgent.new
    configured_agent.connect(
      runtime: :auto,
      adapter_factory: ->(**_kwargs) { configured_adapter }
    )

    expect(configured_agent.session.runtime).must_equal :auto
  ensure
    configured_agent.close unless configured_agent.nil? || configured_agent.closed?
  end

  it "honors class-level auto_handle_tool_calls default" do
    configured_adapter = TestSupport::Voice::FakeAdapter.new
    configured_agent = TestSupport::Voice::ConfiguredVoiceAgent.new
    configured_agent.connect(adapter_factory: ->(**_kwargs) { configured_adapter })
    tool_event = Riffer::Voice::Events::ToolCall.new(
      call_id: "call-6",
      name: TestSupport::Voice::EchoTool.name,
      arguments: {"text" => "ignored-by-default"}
    )
    configured_adapter.emit(tool_event)

    configured_agent.next_event(timeout: 0)

    expect(configured_adapter.tool_responses).must_equal []
  ensure
    configured_agent.close unless configured_agent.nil? || configured_agent.closed?
  end

  it "allows per-read auto_handle_tool_calls override over class-level default" do
    configured_adapter = TestSupport::Voice::FakeAdapter.new
    configured_agent = TestSupport::Voice::ConfiguredVoiceAgent.new(tool_context: {prefix: "voice"})
    configured_agent.connect(adapter_factory: ->(**_kwargs) { configured_adapter })
    tool_event = Riffer::Voice::Events::ToolCall.new(
      call_id: "call-7",
      name: TestSupport::Voice::EchoTool.name,
      arguments: {"text" => "force-handle"}
    )
    configured_adapter.emit(tool_event)

    configured_agent.next_event(timeout: 0, auto_handle_tool_calls: true)

    expect(configured_adapter.tool_responses).must_equal([{call_id: "call-7", result: "voice: force-handle"}])
  ensure
    configured_agent.close unless configured_agent.nil? || configured_agent.closed?
  end

  it "raises helpful errors when resolved model is invalid" do
    invalid_agent_class = Class.new(Riffer::Voice::Agent) do
      model -> { false }
      instructions "Hi"
    end
    invalid_agent = invalid_agent_class.new

    error = expect {
      invalid_agent.connect(adapter_factory: ->(**_kwargs) { TestSupport::Voice::FakeAdapter.new })
    }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "resolved model must be a non-empty String"
  end

  it "raises helpful errors when resolved tools is invalid" do
    invalid_agent_class = Class.new(Riffer::Voice::Agent) do
      model TestSupport::VoiceModels::OPENAI_PROVIDER_MODEL
      instructions "Hi"
      uses_tools -> { "not-an-array" }
    end
    invalid_agent = invalid_agent_class.new

    error = expect {
      invalid_agent.connect(adapter_factory: ->(**_kwargs) { TestSupport::Voice::FakeAdapter.new })
    }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "resolved tools must be an Array"
  end

  it "validates class-level runtime DSL values" do
    error = expect {
      Class.new(Riffer::Voice::Agent) do
        runtime :invalid_runtime
      end
    }.must_raise Riffer::ArgumentError

    expect(error.message).must_include "runtime must be one of"
  end

  it "validates class-level voice_config DSL values" do
    error = expect {
      Class.new(Riffer::Voice::Agent) do
        voice_config "bad"
      end
    }.must_raise Riffer::ArgumentError

    expect(error.message).must_equal "voice_config must be a Hash"
  end

  it "validates connect config values" do
    error = expect {
      agent.connect(
        config: "bad",
        adapter_factory: ->(**_kwargs) { TestSupport::Voice::FakeAdapter.new }
      )
    }.must_raise Riffer::ArgumentError

    expect(error.message).must_equal "config must be a Hash"
  end
end
