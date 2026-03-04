# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::Parsers::DeepgramVoiceAgentParser do
  let(:parser) { Riffer::Voice::Parsers::DeepgramVoiceAgentParser.new }

  it "parses conversation text by role" do
    user_payload = {
      "type" => "ConversationText",
      "role" => "user",
      "content" => "hello"
    }
    assistant_payload = {
      "type" => "ConversationText",
      "role" => "assistant",
      "content" => "hi"
    }

    user_events = parser.call(user_payload)
    assistant_events = parser.call(assistant_payload)

    expect(user_events.map(&:class)).must_equal([Riffer::Voice::Events::InputTranscript])
    expect(user_events.first.text).must_equal("hello")

    expect(assistant_events.map(&:class)).must_equal([Riffer::Voice::Events::OutputTranscript])
    expect(assistant_events.first.text).must_equal("hi")
  end

  it "parses client-side function call requests into tool call events" do
    payload = {
      "type" => "FunctionCallRequest",
      "functions" => [
        {
          "id" => "call_1",
          "name" => "lookup_patient",
          "arguments" => "{\"phone\":\"111\"}",
          "client_side" => true
        },
        {
          "id" => "call_2",
          "name" => "server_tool",
          "arguments" => "{}",
          "client_side" => false
        }
      ]
    }

    events = parser.call(payload)

    expect(events.map(&:class)).must_equal([Riffer::Voice::Events::ToolCall])
    expect(events.first.call_id).must_equal("call_1")
    expect(events.first.name).must_equal("lookup_patient")
    expect(events.first.arguments).must_equal({"phone" => "111"})
  end

  it "normalizes malformed function call arguments to empty hashes" do
    payload = {
      "type" => "FunctionCallRequest",
      "functions" => [
        {
          "id" => "call_1",
          "name" => "lookup_patient",
          "arguments" => "not-json",
          "client_side" => true
        }
      ]
    }

    events = nil
    _output, error_output = capture_io do
      events = parser.call(payload)
    end

    expect(events.map(&:class)).must_equal([Riffer::Voice::Events::ToolCall])
    expect(events.first.arguments).must_equal({})
    expect(error_output).must_include("normalized invalid tool arguments")
  end

  it "maps interrupt and turn completion events" do
    interrupt_events = parser.call({"type" => "UserStartedSpeaking"})
    turn_done_events = parser.call({"type" => "AgentAudioDone"})

    expect(interrupt_events.map(&:class)).must_equal([Riffer::Voice::Events::Interrupt])
    expect(interrupt_events.first.reason).must_equal("user_started_speaking")

    expect(turn_done_events.map(&:class)).must_equal([Riffer::Voice::Events::TurnComplete])
  end

  it "maps warnings and errors" do
    warning_events = parser.call({"type" => "Warning", "code" => "slow_network", "description" => "network lag"})
    error_events = parser.call({"type" => "Error", "code" => "upstream_failure", "message" => "provider failed"})

    expect(warning_events.map(&:class)).must_equal([Riffer::Voice::Events::Error])
    expect(warning_events.first.retriable).must_equal(true)
    expect(warning_events.first.code).must_equal("slow_network")

    expect(error_events.map(&:class)).must_equal([Riffer::Voice::Events::Error])
    expect(error_events.first.retriable).must_equal(false)
    expect(error_events.first.code).must_equal("upstream_failure")
  end

  it "maps injection_refused as a retriable error event" do
    events = parser.call(
      {
        "type" => "InjectionRefused",
        "message" => "Cannot inject message while agent is currently speaking"
      }
    )

    expect(events.map(&:class)).must_equal([Riffer::Voice::Events::Error])
    expect(events.first.retriable).must_equal(true)
    expect(events.first.code).must_equal("injection_refused")
    expect(events.first.message).must_include("Cannot inject message")
  end

  it "maps function call responses into assistant output transcript metadata events" do
    events = parser.call(
      {
        "type" => "FunctionCallResponse",
        "id" => "call_1",
        "name" => "lookup_patient",
        "content" => "{\"status\":\"success\"}"
      }
    )

    expect(events.map(&:class)).must_equal([Riffer::Voice::Events::OutputTranscript])
    expect(events.first.text).must_equal("{\"status\":\"success\"}")
    expect(events.first.is_final).must_equal(true)
    expect(events.first.metadata[:function_call_response]).must_equal(true)
    expect(events.first.metadata[:id]).must_equal("call_1")
    expect(events.first.metadata[:name]).must_equal("lookup_patient")
  end

  it "does not emit executable tool calls from function call response events" do
    events = parser.call(
      {
        "type" => "FunctionCallResponse",
        "id" => "call_2",
        "name" => "server_side_tool",
        "content" => {"ok" => true}
      }
    )

    expect(events.length).must_equal(1)
    expect(events.first).must_be_instance_of(Riffer::Voice::Events::OutputTranscript)
  end

  it "returns empty array for unsupported payloads" do
    expect(parser.call({"type" => "Welcome"})).must_equal([])
  end
end
