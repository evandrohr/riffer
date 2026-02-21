# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::Parsers::OpenAIRealtimeParser do
  let(:parser) { Riffer::Voice::Parsers::OpenAIRealtimeParser.new }

  it "parses audio delta" do
    events = parser.call({"type" => "response.output_audio.delta", "delta" => "BASE64_AUDIO"})

    expect(events.first).must_be_instance_of Riffer::Voice::Events::AudioChunk
    expect(events.first.payload).must_equal "BASE64_AUDIO"
  end

  it "parses input transcript completed" do
    events = parser.call({"type" => "conversation.item.input_audio_transcription.completed", "transcript" => "hello"})

    expect(events.first).must_be_instance_of Riffer::Voice::Events::InputTranscript
    expect(events.first.is_final).must_equal true
  end

  it "parses output transcript done" do
    events = parser.call({"type" => "response.output_audio_transcript.done", "transcript" => "hi"})

    expect(events.first).must_be_instance_of Riffer::Voice::Events::OutputTranscript
    expect(events.first.is_final).must_equal true
  end

  it "parses tool call arguments" do
    events = parser.call(
      {
        "type" => "response.function_call_arguments.done",
        "call_id" => "call_1",
        "name" => "lookup",
        "arguments" => "{\"id\":1}"
      }
    )

    event = events.first
    expect(event).must_be_instance_of Riffer::Voice::Events::ToolCall
    expect(event.arguments).must_equal({"id" => 1})
  end

  it "parses response done with usage and turn complete" do
    events = parser.call(
      {
        "type" => "response.done",
        "response" => {
          "id" => "resp_1",
          "usage" => {
            "input_tokens" => 5,
            "output_tokens" => 7
          }
        }
      }
    )

    expect(events.map(&:class)).must_equal([
      Riffer::Voice::Events::Usage,
      Riffer::Voice::Events::TurnComplete
    ])
  end

  it "parses error event" do
    events = parser.call({"type" => "error", "error" => {"code" => "server_error", "message" => "try again"}})

    expect(events.first).must_be_instance_of Riffer::Voice::Events::Error
    expect(events.first.retriable).must_equal true
  end

  it "parses interrupt events" do
    events = parser.call({"type" => "input_audio_buffer.speech_started"})

    expect(events.first).must_be_instance_of Riffer::Voice::Events::Interrupt
  end
end
