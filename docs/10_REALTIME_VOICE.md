# Realtime Voice

Riffer provides a provider-neutral realtime voice API under `Riffer::Voice`.

Use one public entry point:

- `Riffer::Voice.connect(...)`
- `Riffer::Voice::Session` for send/receive/close lifecycle
- typed events under `Riffer::Voice::Events::*`

## Runtime Dependencies

Realtime voice uses Async websocket transport internally. Add these gems:

```ruby
gem 'async'
gem 'async-http'
gem 'async-websocket'
```

## Configuration

Set provider API keys globally:

```ruby
Riffer.configure do |config|
  config.gemini.api_key = ENV['GEMINI_API_KEY']
  config.openai.api_key = ENV['OPENAI_API_KEY']
end
```

## Model Format

Voice models must use `provider/model` format:

- `openai/gpt-realtime`
- `gemini/gemini-2.5-flash-native-audio-preview-12-2025`

Legacy prefixes such as `openai_realtime/*` and `gemini_live/*` are not supported.

## Runtime Modes

`Riffer::Voice.connect` supports both async/fiber and background/thread execution.

| Mode | Behavior |
| ---- | -------- |
| `:auto` (default) | use current Async task when present; otherwise run background runtime |
| `:async` | require active Async task (fiber-based) |
| `:background` | always run background runtime (thread-based) |

## Session Lifecycle

`Riffer::Voice::Session` methods:

1. `send_text_turn(text:)`
2. `send_audio_chunk(payload:, mime_type:)`
3. `send_tool_response(call_id:, result:)`
4. `events` (Enumerator) and `next_event(timeout:)`
5. `close`

## Migration From Legacy Driver API

If you were using direct driver classes and callbacks, migrate to sessions and event iteration.

Before:

```ruby
driver = Riffer::Voice::Drivers::GeminiLive.new
driver.connect(
  system_prompt: "You are a concise voice assistant.",
  callbacks: {
    on_output_transcript: ->(event) { puts event.text }
  }
)
driver.send_text_turn(text: "Hello")
driver.close
```

After:

```ruby
session = Riffer::Voice.connect(
  model: "gemini/gemini-2.5-flash-native-audio-preview-12-2025",
  system_prompt: "You are a concise voice assistant."
)

begin
  session.send_text_turn(text: "Hello")

  session.events.each do |event|
    case event
    when Riffer::Voice::Events::OutputTranscript
      puts event.text
    when Riffer::Voice::Events::TurnComplete
      break
    end
  end
ensure
  session.close
end
```

Migration checklist:

1. Replace driver construction with `Riffer::Voice.connect`.
2. Replace callback handlers with `session.events` or `session.next_event(timeout:)`.
3. Replace legacy voice model prefixes with `provider/model`.
4. Use `event.arguments_hash` for tool calls.

## End-to-End Example

```ruby
class LookupWeatherTool < Riffer::Tool
  description "Looks up weather for a city"

  params do
    required :city, String
  end

  def call(context:, city:)
    {city: city, forecast: "sunny", temp_c: 22}
  end
end

session = Riffer::Voice.connect(
  model: "gemini/gemini-2.5-flash-native-audio-preview-12-2025",
  system_prompt: "You are a concise voice assistant.",
  tools: [LookupWeatherTool],
  runtime: :auto
)

begin
  session.send_text_turn(text: "What is the weather in Toronto?")

  session.events.each do |event|
    case event
    when Riffer::Voice::Events::OutputTranscript
      puts "[assistant] #{event.text}"
    when Riffer::Voice::Events::ToolCall
      result = LookupWeatherTool.new.call(context: nil, **event.arguments_hash.transform_keys(&:to_sym))
      session.send_tool_response(call_id: event.call_id, result: result)
    when Riffer::Voice::Events::Error
      warn "[voice error] #{event.code}: #{event.message}"
    when Riffer::Voice::Events::TurnComplete
      break
    end
  end
ensure
  session.close
end
```

## Event Types

Voice providers normalize payloads into:

- `AudioChunk`
- `InputTranscript`
- `OutputTranscript`
- `ToolCall`
- `Interrupt`
- `TurnComplete`
- `Usage`
- `Error`

## Provider-Specific Guides

- [Gemini Live Voice Sessions](../docs_providers/07_GEMINI_LIVE.md)
- [OpenAI Realtime Voice Sessions](../docs_providers/08_OPENAI_REALTIME.md)
