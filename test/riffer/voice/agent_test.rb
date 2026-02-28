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

    class ExecutorConfiguredVoiceAgent < Riffer::Voice::Agent
      model VoiceModels::OPENAI_PROVIDER_MODEL
      instructions "Executor configured"
      uses_tools [EchoTool]
      tool_executor lambda { |tool_call_event:, tool_class:, arguments:, context:, agent:|
        response_text = [
          "executor",
          tool_call_event.name,
          tool_class.nil? ? "nil" : tool_class.name,
          arguments[:text],
          context[:prefix],
          agent.class.name
        ].join("|")
        Riffer::Tools::Response.text(response_text)
      }
    end

    class ProfiledVoiceAgent < Riffer::Voice::Agent
      model VoiceModels::OPENAI_PROVIDER_MODEL
      instructions "Base instructions"
      uses_tools [EchoTool]
      runtime :background
      voice_config({
        "temperature" => 0.2,
        "audio" => {
          "input" => {
            "turn_detection" => {
              "type" => "semantic_vad"
            }
          }
        }
      })

      profile :receptionist do
        model "openai/profile-receptionist-model"
        instructions "Receptionist profile"
        uses_tools [RequiredCityTool]
        runtime :auto
        action_budget max_tool_calls: 1
        voice_config({
          "audio" => {
            "input" => {
              "turn_detection" => {
                "create_response" => false
              }
            }
          },
          "profile_label" => "receptionist"
        })
      end

      profile "executor_profile" do
        tool_executor lambda { |tool_call_event:, tool_class:, arguments:, context:, agent:|
          response_text = [
            "profile_executor",
            tool_call_event.name,
            tool_class.nil? ? "nil" : tool_class.name,
            arguments[:text],
            context[:prefix],
            agent.class.name
          ].join("|")
          Riffer::Tools::Response.text(response_text)
        }
      end
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

  it "dispatches on_event and typed callbacks for next_event" do
    seen = []
    agent.on_event { |event| seen << [:on_event, event.class.name] }
    agent.on_output_transcript { |event| seen << [:on_output_transcript, event.text] }
    event = Riffer::Voice::Events::OutputTranscript.new(text: "hello from assistant")
    adapter.emit(event)

    received = agent.next_event(timeout: 0)

    expect(received).must_equal event
    expect(seen).must_equal([
      [:on_event, "Riffer::Voice::Events::OutputTranscript"],
      [:on_output_transcript, "hello from assistant"]
    ])
  end

  it "dispatches typed callbacks while iterating events enumerator" do
    seen = []
    agent.on_turn_complete { |_event| seen << :on_turn_complete }
    done_event = Riffer::Voice::Events::TurnComplete.new
    adapter.emit(done_event)

    agent.events.each do |event|
      break if event == done_event
    end

    expect(seen).must_equal([:on_turn_complete])
  end

  it "dispatches on_error callbacks for error events" do
    seen_codes = []
    agent.on_error { |event| seen_codes << event.code }
    error_event = Riffer::Voice::Events::Error.new(code: "provider_timeout", message: "try again")
    adapter.emit(error_event)

    received = agent.next_event(timeout: 0)

    expect(received).must_equal error_event
    expect(seen_codes).must_equal(["provider_timeout"])
  end

  it "raises deterministic errors when a callback fails" do
    agent.on_output_transcript { |_event| raise "boom" }
    adapter.emit(Riffer::Voice::Events::OutputTranscript.new(text: "x"))

    error = expect {
      agent.next_event(timeout: 0)
    }.must_raise Riffer::Error

    expect(error.message).must_equal(
      "on_output_transcript callback failed for Riffer::Voice::Events::OutputTranscript: RuntimeError: boom"
    )
  end

  it "validates callback registration blocks" do
    error = expect { agent.on_event }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "on_event requires a block"

    error = expect { agent.on_tool_call }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "on_tool_call requires a block"
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

  it "uses custom tool_executor from initialize for automatic tool handling" do
    custom_agent = TestSupport::Voice::SupportVoiceAgent.new(
      tool_context: {prefix: "ctx"},
      tool_executor: lambda { |tool_call_event:, tool_class:, arguments:, context:, agent:|
        response_text = [
          "custom",
          tool_call_event.name,
          tool_class.nil? ? "nil" : tool_class.name,
          arguments[:text],
          context[:prefix],
          agent.class.name
        ].join("|")
        Riffer::Tools::Response.text(response_text)
      }
    )
    custom_adapter = TestSupport::Voice::FakeAdapter.new
    custom_agent.connect(runtime: :background, adapter_factory: ->(**_kwargs) { custom_adapter })
    custom_adapter.emit(
      Riffer::Voice::Events::ToolCall.new(
        call_id: "call-8",
        name: TestSupport::Voice::EchoTool.name,
        arguments: {"text" => "hello"}
      )
    )

    custom_agent.next_event(timeout: 0)

    expect(custom_adapter.tool_responses).must_equal([
      {
        call_id: "call-8",
        result: "custom|#{TestSupport::Voice::EchoTool.name}|#{TestSupport::Voice::EchoTool.name}|hello|ctx|#{TestSupport::Voice::SupportVoiceAgent.name}"
      }
    ])
  ensure
    custom_agent.close unless custom_agent.nil? || custom_agent.closed?
  end

  it "uses class-level tool_executor when one is configured" do
    configured_agent = TestSupport::Voice::ExecutorConfiguredVoiceAgent.new(tool_context: {prefix: "class_ctx"})
    configured_adapter = TestSupport::Voice::FakeAdapter.new
    configured_agent.connect(runtime: :background, adapter_factory: ->(**_kwargs) { configured_adapter })
    configured_adapter.emit(
      Riffer::Voice::Events::ToolCall.new(
        call_id: "call-9",
        name: TestSupport::Voice::EchoTool.name,
        arguments: {"text" => "hello"}
      )
    )

    configured_agent.next_event(timeout: 0)

    expect(configured_adapter.tool_responses).must_equal([
      {
        call_id: "call-9",
        result: "executor|#{TestSupport::Voice::EchoTool.name}|#{TestSupport::Voice::EchoTool.name}|hello|class_ctx|#{TestSupport::Voice::ExecutorConfiguredVoiceAgent.name}"
      }
    ])
  ensure
    configured_agent.close unless configured_agent.nil? || configured_agent.closed?
  end

  it "invokes before and after tool execution hooks" do
    hook_events = []
    agent.on_before_tool_execution do |payload|
      hook_events << [:before, payload[:tool_name], payload[:arguments][:text]]
    end
    agent.on_after_tool_execution do |payload|
      hook_events << [:after, payload[:tool_name], payload[:result].content]
    end
    adapter.emit(
      Riffer::Voice::Events::ToolCall.new(
        call_id: "call-10",
        name: TestSupport::Voice::EchoTool.name,
        arguments: {"text" => "hooks"}
      )
    )

    agent.next_event(timeout: 0)

    expect(hook_events).must_equal([
      [:before, TestSupport::Voice::EchoTool.name, "hooks"],
      [:after, TestSupport::Voice::EchoTool.name, "voice: hooks"]
    ])
  end

  it "invokes tool execution error hook for schema-hash declared tools without tool_executor" do
    schema_agent = Riffer::Voice::Agent.new
    schema_adapter = TestSupport::Voice::FakeAdapter.new
    schema_errors = []
    schema_agent.on_tool_execution_error do |payload|
      schema_errors << [payload[:tool_name], payload[:result].error_type]
    end
    schema_agent.connect(
      model: TestSupport::VoiceModels::OPENAI_PROVIDER_MODEL,
      system_prompt: "You are helpful",
      tools: [{type: "function", name: "external_lookup", parameters: {type: "object", properties: {}}}],
      runtime: :background,
      adapter_factory: ->(**_kwargs) { schema_adapter }
    )
    schema_adapter.emit(
      Riffer::Voice::Events::ToolCall.new(
        call_id: "call-11",
        name: "external_lookup",
        arguments: {}
      )
    )

    schema_agent.next_event(timeout: 0)

    payload = schema_adapter.tool_responses.first[:result]
    expect(payload).must_be_instance_of Hash
    expect(payload.dig("error", "type")).must_equal "external_tool_executor_required"
    expect(schema_errors).must_equal([["external_lookup", :external_tool_executor_required]])
  ensure
    schema_agent.close unless schema_agent.nil? || schema_agent.closed?
  end

  it "validates tool_executor input on initialize and connect" do
    error = expect {
      Riffer::Voice::Agent.new(tool_executor: "bad")
    }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "tool_executor must respond to #call"

    error = expect {
      agent.connect(
        tool_executor: "bad",
        adapter_factory: ->(**_kwargs) { TestSupport::Voice::FakeAdapter.new }
      )
    }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "tool_executor must respond to #call"
  end

  it "applies profile overrides for model/instructions/tools/runtime/config" do
    profiled_agent = TestSupport::Voice::ProfiledVoiceAgent.new
    profiled_adapter = TestSupport::Voice::FakeAdapter.new
    profiled_agent.connect(profile: :receptionist, adapter_factory: ->(**_kwargs) { profiled_adapter })

    expect(profiled_agent.session.model).must_equal "openai/profile-receptionist-model"
    expect(profiled_agent.session.runtime).must_equal :auto
    connect_call = profiled_adapter.connect_calls.first
    expect(connect_call[:system_prompt]).must_equal "Receptionist profile"
    expect(connect_call[:tools]).must_equal([TestSupport::Voice::RequiredCityTool])
    expect(connect_call[:config]).must_equal({
      "temperature" => 0.2,
      "audio" => {
        "input" => {
          "turn_detection" => {
            "type" => "semantic_vad",
            "create_response" => false
          }
        }
      },
      "profile_label" => "receptionist"
    })
    expect(profiled_agent.action_budget_state[:max_tool_calls]).must_equal 1
  ensure
    profiled_agent.close unless profiled_agent.nil? || profiled_agent.closed?
  end

  it "allows explicit connect arguments to override selected profile values" do
    profiled_agent = TestSupport::Voice::ProfiledVoiceAgent.new
    profiled_adapter = TestSupport::Voice::FakeAdapter.new
    profiled_agent.connect(
      profile: :receptionist,
      model: TestSupport::VoiceModels::OPENAI_PROVIDER_MODEL,
      system_prompt: "Explicit system prompt",
      tools: [TestSupport::Voice::EchoTool],
      runtime: :background,
      config: {"temperature" => 0.9},
      adapter_factory: ->(**_kwargs) { profiled_adapter }
    )

    expect(profiled_agent.session.model).must_equal TestSupport::VoiceModels::OPENAI_PROVIDER_MODEL
    expect(profiled_agent.session.runtime).must_equal :background
    connect_call = profiled_adapter.connect_calls.first
    expect(connect_call[:system_prompt]).must_equal "Explicit system prompt"
    expect(connect_call[:tools]).must_equal([TestSupport::Voice::EchoTool])
    expect(connect_call[:config]).must_equal({
      "temperature" => 0.9,
      "audio" => {
        "input" => {
          "turn_detection" => {
            "type" => "semantic_vad",
            "create_response" => false
          }
        }
      },
      "profile_label" => "receptionist"
    })
  ensure
    profiled_agent.close unless profiled_agent.nil? || profiled_agent.closed?
  end

  it "uses profile tool_executor when selected" do
    profiled_agent = TestSupport::Voice::ProfiledVoiceAgent.new(tool_context: {prefix: "profile_ctx"})
    profiled_adapter = TestSupport::Voice::FakeAdapter.new
    profiled_agent.connect(
      profile: "executor_profile",
      runtime: :background,
      tools: [TestSupport::Voice::EchoTool],
      adapter_factory: ->(**_kwargs) { profiled_adapter }
    )
    profiled_adapter.emit(
      Riffer::Voice::Events::ToolCall.new(
        call_id: "call-12",
        name: TestSupport::Voice::EchoTool.name,
        arguments: {"text" => "hello"}
      )
    )

    profiled_agent.next_event(timeout: 0)

    expect(profiled_adapter.tool_responses).must_equal([
      {
        call_id: "call-12",
        result: "profile_executor|#{TestSupport::Voice::EchoTool.name}|#{TestSupport::Voice::EchoTool.name}|hello|profile_ctx|#{TestSupport::Voice::ProfiledVoiceAgent.name}"
      }
    ])
  ensure
    profiled_agent.close unless profiled_agent.nil? || profiled_agent.closed?
  end

  it "raises helpful errors for invalid profile selection" do
    error = expect {
      agent.connect(
        profile: :missing_profile,
        adapter_factory: ->(**_kwargs) { TestSupport::Voice::FakeAdapter.new }
      )
    }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "unknown profile 'missing_profile'"

    error = expect {
      agent.connect(
        profile: "",
        adapter_factory: ->(**_kwargs) { TestSupport::Voice::FakeAdapter.new }
      )
    }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "profile must be a non-empty String or Symbol"
  end

  it "validates profile DSL declaration inputs" do
    error = expect {
      Class.new(Riffer::Voice::Agent) do
        profile 123 do
          runtime :background
        end
      end
    }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "profile name must be a non-empty String or Symbol"

    error = expect {
      Class.new(Riffer::Voice::Agent) do
        profile :invalid_profile do
          runtime :bad_runtime
        end
      end
    }.must_raise Riffer::ArgumentError
    expect(error.message).must_include "runtime must be one of"

    error = expect {
      Class.new(Riffer::Voice::Agent) do
        profile :invalid_profile do
          voice_config "bad"
        end
      end
    }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "profile voice_config must be a Hash"
  end

  it "enforces max_tool_calls action budget with typed policy error" do
    budget_agent = TestSupport::Voice::SupportVoiceAgent.new(
      tool_context: {prefix: "voice"},
      action_budget: {max_tool_calls: 1}
    )
    budget_adapter = TestSupport::Voice::FakeAdapter.new
    budget_agent.connect(runtime: :background, adapter_factory: ->(**_kwargs) { budget_adapter })
    budget_adapter.emit(
      Riffer::Voice::Events::ToolCall.new(
        call_id: "call-13",
        name: TestSupport::Voice::EchoTool.name,
        arguments: {"text" => "first"}
      )
    )
    budget_adapter.emit(
      Riffer::Voice::Events::ToolCall.new(
        call_id: "call-14",
        name: TestSupport::Voice::EchoTool.name,
        arguments: {"text" => "second"}
      )
    )

    budget_agent.next_event(timeout: 0)
    budget_agent.next_event(timeout: 0)

    expect(budget_adapter.tool_responses.first[:result]).must_equal "voice: first"
    error_payload = budget_adapter.tool_responses.last[:result]
    expect(error_payload).must_be_instance_of Hash
    expect(error_payload.dig("error", "type")).must_equal "tool_call_budget_exceeded"
    expect(budget_agent.action_budget_state).must_equal({
      max_tool_calls: 1,
      max_mutation_calls: nil,
      tool_calls: 1,
      mutation_tool_calls: 0
    })
  ensure
    budget_agent.close unless budget_agent.nil? || budget_agent.closed?
  end

  it "enforces mutation budget using mutation_classifier hook" do
    mutation_agent = TestSupport::Voice::SupportVoiceAgent.new(
      tool_context: {prefix: "voice"},
      action_budget: {max_mutation_calls: 1},
      mutation_classifier: ->(**_kwargs) { true }
    )
    mutation_adapter = TestSupport::Voice::FakeAdapter.new
    mutation_agent.connect(runtime: :background, adapter_factory: ->(**_kwargs) { mutation_adapter })
    mutation_adapter.emit(
      Riffer::Voice::Events::ToolCall.new(
        call_id: "call-15",
        name: TestSupport::Voice::EchoTool.name,
        arguments: {"text" => "first"}
      )
    )
    mutation_adapter.emit(
      Riffer::Voice::Events::ToolCall.new(
        call_id: "call-16",
        name: TestSupport::Voice::EchoTool.name,
        arguments: {"text" => "second"}
      )
    )

    mutation_agent.next_event(timeout: 0)
    mutation_agent.next_event(timeout: 0)

    expect(mutation_adapter.tool_responses.first[:result]).must_equal "voice: first"
    error_payload = mutation_adapter.tool_responses.last[:result]
    expect(error_payload).must_be_instance_of Hash
    expect(error_payload.dig("error", "type")).must_equal "mutation_budget_exceeded"
    expect(mutation_agent.action_budget_state).must_equal({
      max_tool_calls: nil,
      max_mutation_calls: 1,
      tool_calls: 1,
      mutation_tool_calls: 1
    })
  ensure
    mutation_agent.close unless mutation_agent.nil? || mutation_agent.closed?
  end

  it "supports tool_policy and approval_callback gating" do
    policy_agent = TestSupport::Voice::SupportVoiceAgent.new(
      tool_context: {prefix: "voice"},
      tool_policy: ->(**_kwargs) { :require_approval },
      approval_callback: ->(**_kwargs) { true }
    )
    policy_adapter = TestSupport::Voice::FakeAdapter.new
    policy_agent.connect(runtime: :background, adapter_factory: ->(**_kwargs) { policy_adapter })
    policy_adapter.emit(
      Riffer::Voice::Events::ToolCall.new(
        call_id: "call-17",
        name: TestSupport::Voice::EchoTool.name,
        arguments: {"text" => "approved"}
      )
    )

    policy_agent.next_event(timeout: 0)

    expect(policy_adapter.tool_responses).must_equal([{call_id: "call-17", result: "voice: approved"}])
  ensure
    policy_agent.close unless policy_agent.nil? || policy_agent.closed?
  end

  it "returns typed policy_denied errors when tool_policy denies dispatch" do
    denied_agent = TestSupport::Voice::SupportVoiceAgent.new(
      tool_policy: ->(**_kwargs) { :deny }
    )
    denied_adapter = TestSupport::Voice::FakeAdapter.new
    denied_agent.connect(runtime: :background, adapter_factory: ->(**_kwargs) { denied_adapter })
    denied_adapter.emit(
      Riffer::Voice::Events::ToolCall.new(
        call_id: "call-18-deny",
        name: TestSupport::Voice::EchoTool.name,
        arguments: {"text" => "deny"}
      )
    )

    denied_agent.next_event(timeout: 0)

    payload = denied_adapter.tool_responses.first[:result]
    expect(payload).must_be_instance_of Hash
    expect(payload.dig("error", "type")).must_equal "policy_denied"
  ensure
    denied_agent.close unless denied_agent.nil? || denied_agent.closed?
  end

  it "returns typed approval_required errors when approval callback is absent" do
    approval_required_agent = TestSupport::Voice::SupportVoiceAgent.new(
      tool_policy: ->(**_kwargs) { :require_approval }
    )
    approval_required_adapter = TestSupport::Voice::FakeAdapter.new
    approval_required_agent.connect(runtime: :background, adapter_factory: ->(**_kwargs) { approval_required_adapter })
    approval_required_adapter.emit(
      Riffer::Voice::Events::ToolCall.new(
        call_id: "call-18",
        name: TestSupport::Voice::EchoTool.name,
        arguments: {"text" => "blocked"}
      )
    )
    approval_required_agent.next_event(timeout: 0)
    required_payload = approval_required_adapter.tool_responses.first[:result]
    expect(required_payload.dig("error", "type")).must_equal "approval_required"
  ensure
    approval_required_agent.close unless approval_required_agent.nil? || approval_required_agent.closed?
  end

  it "validates action_budget and policy hook inputs" do
    error = expect {
      Riffer::Voice::Agent.new(action_budget: "bad")
    }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "action_budget must be a Hash"

    error = expect {
      Class.new(Riffer::Voice::Agent) do
        action_budget max_tool_calls: 0
      end
    }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "action_budget[max_tool_calls] must be nil or an Integer > 0"

    error = expect {
      Riffer::Voice::Agent.new(tool_policy: "bad")
    }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "tool_policy must respond to #call"

    error = expect {
      Riffer::Voice::Agent.new(approval_callback: "bad")
    }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "approval_callback must respond to #call"
  end

  it "runs loop until interrupt and yields consumed events" do
    output_event = Riffer::Voice::Events::OutputTranscript.new(text: "hello")
    interrupt_event = Riffer::Voice::Events::Interrupt.new(reason: :barge_in)
    trailing_event = Riffer::Voice::Events::TurnComplete.new
    adapter.emit(output_event)
    adapter.emit(interrupt_event)
    adapter.emit(trailing_event)

    seen = []
    returned = agent.run_loop do |event|
      seen << event
    end

    expect(returned).must_equal agent
    expect(seen).must_equal([output_event, interrupt_event])
    remaining = agent.drain_available_events
    expect(remaining).must_equal([trailing_event])
  end

  it "run_until_turn_complete sends optional text and stops at turn completion" do
    loop_agent = TestSupport::Voice::SupportVoiceAgent.new
    loop_adapter = TestSupport::Voice::FakeAdapter.new
    loop_agent.connect(runtime: :background, adapter_factory: ->(**_kwargs) { loop_adapter })
    output_event = Riffer::Voice::Events::OutputTranscript.new(text: "processing")
    complete_event = Riffer::Voice::Events::TurnComplete.new
    trailing_event = Riffer::Voice::Events::Usage.new(input_tokens: 1)
    loop_adapter.emit(output_event)
    loop_adapter.emit(complete_event)
    loop_adapter.emit(trailing_event)

    events = loop_agent.run_until_turn_complete(text: "hello")

    expect(loop_adapter.text_turns).must_equal(["hello"])
    expect(events).must_equal([output_event, complete_event])
    expect(loop_agent.drain_available_events).must_equal([trailing_event])
  ensure
    loop_agent.close unless loop_agent.nil? || loop_agent.closed?
  end

  it "drains available events with optional max_events limit" do
    first = Riffer::Voice::Events::OutputTranscript.new(text: "one")
    second = Riffer::Voice::Events::OutputTranscript.new(text: "two")
    third = Riffer::Voice::Events::OutputTranscript.new(text: "three")
    adapter.emit(first)
    adapter.emit(second)
    adapter.emit(third)

    first_batch = agent.drain_available_events(max_events: 2)
    second_batch = agent.drain_available_events

    expect(first_batch).must_equal([first, second])
    expect(second_batch).must_equal([third])
  end

  it "validates run helper input contracts" do
    error = expect { agent.run_loop(timeout: -1) { |_event| nil } }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "timeout must be nil or >= 0"

    error = expect { agent.run_until_turn_complete(timeout: -1) }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "timeout must be nil or >= 0"

    error = expect { agent.drain_available_events(max_events: 0) }.must_raise Riffer::ArgumentError
    expect(error.message).must_equal "max_events must be nil or an Integer > 0"
  end
end
