# Realtime Voice

Riffer provides a provider-neutral realtime voice API under `Riffer::Voice`.

Use one public entry point:

- `Riffer::Voice.connect(...)`
- `Riffer::Voice::Session` for send/receive/close lifecycle
- `Riffer::Voice::Agent` for optional session orchestration + automatic tool execution
- typed events under `Riffer::Voice::Events::*`

## Runtime Dependencies

Realtime voice selects transport by runtime mode:

```ruby
# For async/fiber runtime (:async, or :auto with Async task)
gem 'async'
gem 'async-http'
gem 'async-websocket'

# For background/thread runtime (:background, or :auto without Async task)
gem 'websocket-client-simple'
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

- `openai/gpt-realtime-1.5`
- `gemini/gemini-2.5-flash-native-audio-preview-12-2025`

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

## Voice Agent (Optional Orchestration)

`Riffer::Voice::Agent` wraps `Riffer::Voice::Session` and can automatically execute
`Riffer::Tool` calls emitted as `Riffer::Voice::Events::ToolCall`.

```ruby
class LookupWeatherTool < Riffer::Tool
  identifier "lookup_weather"
  description "Looks up weather for a city"

  params do
    required :city, String
  end

  def call(context:, city:)
    text("The weather in #{city} is sunny.")
  end
end

class SupportVoiceAgent < Riffer::Voice::Agent
  model "openai/gpt-realtime-1.5"
  instructions "You are a concise voice assistant."
  uses_tools [LookupWeatherTool]
  runtime :background
  voice_config(
    "audio" => {
      "input" => {
        "turn_detection" => {"type" => "semantic_vad"}
      }
    }
  )
  auto_handle_tool_calls true
end

agent = SupportVoiceAgent.connect(runtime: :auto, tool_context: {account_id: "acct_123"})

begin
  agent.send_text_turn(text: "What's the weather in Toronto?")

  agent.events.each do |event|
    case event
    when Riffer::Voice::Events::OutputTranscript
      puts "[assistant] #{event.text}"
    when Riffer::Voice::Events::TurnComplete
      break
    end
  end
ensure
  agent.close
end
```

Notes:

- `Riffer::Voice::Agent` keeps the underlying `session` available.
- Automatic tool handling can be disabled per read:
  - `agent.next_event(auto_handle_tool_calls: false)`
  - `agent.events(auto_handle_tool_calls: false)`
- Tool errors (unknown tool, validation, timeout, execution) are sent back through `send_tool_response`.

### Voice Agent Defaults and Precedence

`Riffer::Voice::Agent` supports class-level defaults:

- `runtime :auto | :async | :background`
- `voice_config({...})` (default connect config payload)
- `auto_handle_tool_calls true | false`

`connect(...)` precedence is:

1. explicit method arguments
2. class-level defaults
3. built-in fallback (`runtime: :auto`, empty `voice_config`, auto tool handling `true`)

`voice_config` is deep-merged with `connect(config: ...)`, where explicit `connect` values win.

## Validation and Error Behavior

`Riffer::Voice.connect(...)` validates:

- `model` and `system_prompt` are non-empty strings
- `tools` is an array with valid entries
- each tool entry must be either:
  - a `Riffer::Tool` class
  - an OpenAI-style function schema hash
  - a Gemini-style function declaration hash

Runtime and transport failures follow fail-fast semantics:

- `send_text_turn`, `send_audio_chunk`, and `send_tool_response` raise on write failure
- provider/runtime errors are still emitted as `Riffer::Voice::Events::Error`
- connect failures preserve underlying exception context (no silent false success)

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
