# frozen_string_literal: true

require "test_helper"

describe Riffer::Voice::Parsers::GeminiLiveParser do
  let(:parser) { Riffer::Voice::Parsers::GeminiLiveParser.new }

  it "parses audio, transcript, tool call, interrupt, turn complete and usage" do
    payload = {
      "serverContent" => {
        "modelTurn" => {
          "parts" => [
            {
              "inlineData" => {
                "data" => "BASE64_AUDIO",
                "mimeType" => "audio/pcm;rate=24000"
              }
            }
          ]
        },
        "inputTranscription" => {
          "text" => "hello",
          "isFinal" => true
        },
        "outputTranscription" => {
          "text" => "hi there",
          "isFinal" => false
        },
        "interrupted" => true,
        "turnComplete" => true
      },
      "toolCall" => {
        "functionCalls" => [
          {
            "id" => "call_123",
            "name" => "lookup_patient",
            "args" => {"phone" => "111"}
          }
        ]
      },
      "usageMetadata" => {
        "promptTokenCount" => 11,
        "candidatesTokenCount" => 12,
        "inputAudioTokenCount" => 13,
        "outputAudioTokenCount" => 14
      }
    }

    events = parser.call(payload)

    expect(events.map(&:class)).must_equal [
      Riffer::Voice::Events::AudioChunk,
      Riffer::Voice::Events::InputTranscript,
      Riffer::Voice::Events::OutputTranscript,
      Riffer::Voice::Events::ToolCall,
      Riffer::Voice::Events::Interrupt,
      Riffer::Voice::Events::TurnComplete,
      Riffer::Voice::Events::Usage
    ]
  end

  it "returns empty array for unsupported payload" do
    expect(parser.call({"foo" => "bar"})).must_equal []
  end
end
