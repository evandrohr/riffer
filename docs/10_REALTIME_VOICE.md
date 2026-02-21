# Realtime Voice

Riffer includes a provider-neutral realtime voice subsystem under `Riffer::Voice`.

It is built around:

- Voice drivers (`Riffer::Voice::Drivers::*`)
- Typed realtime events (`Riffer::Voice::Events::*`)
- Async websocket transport (`Riffer::Voice::Transports::AsyncWebsocket`)

## Available Drivers

| Driver Class | Repository Identifier | Provider |
| ------------ | --------------------- | -------- |
| `Riffer::Voice::Drivers::GeminiLive` | `:gemini_live` | Gemini Live |
| `Riffer::Voice::Drivers::OpenAIRealtime` | `:openai_realtime` | OpenAI Realtime GA |

Use the voice driver repository to resolve drivers dynamically:

```ruby
driver_class = Riffer::Voice::Drivers::Repository.find(:gemini_live)
driver = driver_class.new
```

## Runtime Dependencies

Realtime voice requires Async websocket libraries at runtime:

```ruby
gem 'async'
gem 'async-http'
gem 'async-websocket'
```

## Configuration

Configure API keys globally:

```ruby
Riffer.configure do |config|
  config.gemini.api_key = ENV['GEMINI_API_KEY']
  config.openai.api_key = ENV['OPENAI_API_KEY']
end
```

## Driver Lifecycle

All drivers implement the same core lifecycle:

1. `connect(system_prompt:, tools:, config:, callbacks:)`
2. `send_audio_chunk(payload:, mime_type:)`
3. `send_text_turn(text:, role:)`
4. `send_tool_response(call_id:, result:)`
5. `close(reason:)`

`connect` must run inside an Async task context.

## Callbacks

Callbacks are configured via `callbacks:` in `connect`.

| Callback | Event Class |
| -------- | ----------- |
| `on_event` | Any `Riffer::Voice::Events::Base` subclass |
| `on_audio_chunk` | `Riffer::Voice::Events::AudioChunk` |
| `on_input_transcript` | `Riffer::Voice::Events::InputTranscript` |
| `on_output_transcript` | `Riffer::Voice::Events::OutputTranscript` |
| `on_tool_call` | `Riffer::Voice::Events::ToolCall` |
| `on_interrupt` | `Riffer::Voice::Events::Interrupt` |
| `on_turn_complete` | `Riffer::Voice::Events::TurnComplete` |
| `on_usage` | `Riffer::Voice::Events::Usage` |
| `on_error` | `Riffer::Voice::Events::Error` |

## End-to-End Example

```ruby
require 'async'
require 'json'

class LookupWeatherTool < Riffer::Tool
  description "Looks up weather for a city"

  params do
    required :city, String
  end

  def call(context:, city:)
    {city: city, forecast: "sunny", temp_c: 22}
  end
end

Async do
  driver = Riffer::Voice::Drivers::GeminiLive.new

  begin
    driver.connect(
      system_prompt: "You are a concise voice assistant.",
      tools: [LookupWeatherTool],
      callbacks: {
        on_output_transcript: ->(event) { puts "[assistant] #{event.text}" },
        on_tool_call: lambda do |event|
          args = event.arguments.is_a?(String) ? JSON.parse(event.arguments) : event.arguments
          result = LookupWeatherTool.new.call(context: nil, city: args.fetch("city", args[:city]))
          driver.send_tool_response(call_id: event.call_id, result: result)
        end,
        on_error: ->(event) { warn "[voice error] #{event.code}: #{event.message}" }
      }
    )

    # Text turn
    driver.send_text_turn(text: "What is the weather in Toronto?")

    # Audio turn (base64-encoded PCM payload)
    # driver.send_audio_chunk(payload: base64_pcm_chunk, mime_type: "audio/pcm;rate=16000")

    sleep 2
  ensure
    driver&.close(reason: "session_complete")
  end
end
```

## Provider-Specific Guides

- [Gemini Live Voice Driver](../docs_providers/07_GEMINI_LIVE.md)
- [OpenAI Realtime Voice Driver](../docs_providers/08_OPENAI_REALTIME.md)
