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

## Session vs Voice Agent

Use `Riffer::Voice::Session` when you want low-level control over transport/event loops.

Use `Riffer::Voice::Agent` when you want orchestration conveniences:

- automatic tool-call handling
- callback registry
- profiles/policy/budget controls
- run-loop helper methods
- durability checkpoints and metadata snapshots

Quick rule:

- start with `Session` for provider/debug/transport work
- start with `Voice::Agent` for product/application voice behaviors

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

### Voice Agent Profiles

Profiles let one `Riffer::Voice::Agent` class expose multiple role-like runtime bundles.

```ruby
class SupportVoiceAgent < Riffer::Voice::Agent
  model "openai/gpt-realtime-1.5"
  instructions "Base assistant behavior."
  uses_tools [LookupWeatherTool]
  runtime :background
  voice_config("temperature" => 0.2)

  profile :receptionist do
    instructions "Receptionist behavior."
    runtime :auto
    uses_tools []
    voice_config("temperature" => 0.0)
  end
end

agent = SupportVoiceAgent.connect(profile: :receptionist)
```

Supported profile fields:

- `model`
- `instructions`
- `uses_tools`
- `runtime`
- `voice_config`
- `tool_executor`
- `action_budget`
- `mutation_classifier`
- `tool_policy`
- `approval_callback`

Precedence with profiles is:

1. explicit `connect(...)` arguments
2. selected profile values
3. class-level defaults
4. built-in fallback defaults

### Voice Agent Event Callbacks

`Riffer::Voice::Agent` supports callback registration over normalized typed events:

- `on_event`
- `on_audio_chunk`
- `on_input_transcript`
- `on_output_transcript`
- `on_tool_call`
- `on_interrupt`
- `on_turn_complete`
- `on_usage`
- `on_error`

Callbacks are invoked when events are consumed through `next_event` or `events`.

```ruby
agent = SupportVoiceAgent.connect

agent.on_event { |event| puts "[event] #{event.class.name}" }
agent.on_tool_call { |event| puts "[tool] #{event.name}" }
agent.on_error { |event| warn "[voice error] #{event.code}: #{event.message}" }
```

Callback failure policy is explicit and fail-fast:

- if any callback raises, `Riffer::Error` is raised with callback key and event class context
- callback errors are never silently dropped

### Voice Agent Tool Executor and Hooks

Automatic tool handling supports a pluggable executor:

- default behavior uses `Riffer::Tool#call_with_validation` for class-based tools
- custom behavior can be injected with `tool_executor` (class-level or instance-level)

```ruby
class SupportVoiceAgent < Riffer::Voice::Agent
  model "openai/gpt-realtime-1.5"
  instructions "You are a concise voice assistant."
  uses_tools [LookupWeatherTool]

  tool_executor lambda { |tool_call_event:, tool_class:, arguments:, context:, agent:|
    # custom routing logic (for example, external operation runners)
    tool_class.new.call_with_validation(context: context, **arguments)
  }
end
```

Lifecycle hooks are available for automatic tool execution:

- `on_before_tool_execution`
- `on_after_tool_execution`
- `on_tool_execution_error`

Each hook receives a payload hash including tool metadata (`tool_name`, `tool_class`, `arguments`, `event`) and `result`/`error` when applicable.

Schema-hash declared tools (non-`Riffer::Tool` classes) have explicit behavior:

- without `tool_executor`: response error type is `external_tool_executor_required`
- with `tool_executor`: dispatch is delegated to the custom executor

### Voice Agent Policy Gates and Action Budgets

`Riffer::Voice::Agent` can apply dispatch-time governance before automatic tool execution:

- action budgets (`max_tool_calls`, `max_mutation_calls`)
- mutation classifier hook (`mutation_classifier`)
- policy hook (`tool_policy`)
- approval hook (`approval_callback`)

```ruby
agent = SupportVoiceAgent.connect(
  action_budget: {max_tool_calls: 10, max_mutation_calls: 2},
  mutation_classifier: ->(tool_name:, **_) { tool_name.start_with?("write_") },
  tool_policy: ->(mutation_call:, **_) { mutation_call ? :require_approval : :allow },
  approval_callback: ->(**_) { true }
)
```

Policy outcomes are serialized into typed tool errors when blocked:

- `tool_call_budget_exceeded`
- `mutation_budget_exceeded`
- `policy_denied`
- `approval_required`
- `approval_denied`
- `approval_error`

### Voice Agent Run Helpers

`Riffer::Voice::Agent` includes helpers to reduce manual event-loop boilerplate:

- `run_loop(timeout:) { |event| ... }`
- `run_until_turn_complete(text:, timeout:)`
- `drain_available_events(max_events:)`

```ruby
events = agent.run_until_turn_complete(text: "Help me reset my password", timeout: 10)

agent.run_loop(timeout: 5) do |event|
  break if event.is_a?(Riffer::Voice::Events::TurnComplete)
end

pending = agent.drain_available_events(max_events: 20)
```

Run-loop stop conditions:

- timeout reached (when provided)
- disconnected/closed session
- `Interrupt` event (for `run_loop`)
- `TurnComplete` or `Interrupt` event (for `run_until_turn_complete`)

### Voice Agent Durability Hooks

For app-managed durability/resume workflows, `Riffer::Voice::Agent` can emit checkpoints:

- `on_turn_complete_checkpoint`
- `on_tool_request_checkpoint`
- `on_tool_response_checkpoint`
- `on_recoverable_error_checkpoint`
- `on_checkpoint` (receives all checkpoint types)

Checkpoint payloads include a stable `type`, timestamp, active profile, and current budget state.

```ruby
agent.on_checkpoint do |payload|
  puts "checkpoint=#{payload[:type]} at=#{payload[:at]}"
end
```

Lightweight orchestration metadata can be snapshotted/restored:

- `export_state_snapshot`
- `import_state_snapshot(snapshot: ...)`

This snapshot is agent-side metadata only (profile, counters, budget config, auto-tool handling flag).  
Transport/provider connection state is intentionally not serialized.

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

## Migration From Manual Session Loops

Before (manual `Session` loop):

```ruby
session = Riffer::Voice.connect(...)

begin
  session.send_text_turn(text: "Help me")

  loop do
    event = session.next_event(timeout: 5)
    break if event.nil?

    case event
    when Riffer::Voice::Events::ToolCall
      result = MyTool.new.call(context: nil, **event.arguments_hash.transform_keys(&:to_sym))
      session.send_tool_response(call_id: event.call_id, result: result)
    when Riffer::Voice::Events::TurnComplete, Riffer::Voice::Events::Interrupt
      break
    end
  end
ensure
  session.close
end
```

After (`Voice::Agent` orchestration):

```ruby
class SupportVoiceAgent < Riffer::Voice::Agent
  model "openai/gpt-realtime-1.5"
  instructions "You are a concise voice assistant."
  uses_tools [MyTool]
end

agent = SupportVoiceAgent.connect

begin
  events = agent.run_until_turn_complete(text: "Help me", timeout: 5)
  puts "processed #{events.length} events"
ensure
  agent.close
end
```

If you need direct loop control but still want orchestration features:

```ruby
agent.run_loop(timeout: 10) do |event|
  break if event.is_a?(Riffer::Voice::Events::TurnComplete)
end
```

## Responsibility Boundary

`Riffer::Voice::Agent` intentionally focuses on runtime orchestration only.

Application responsibilities remain outside Riffer core:

- telephony integrations (Twilio/Telnyx/etc.)
- persistent workflow storage
- durable job scheduling/retries
- skill/authoring management planes

Use checkpoints and snapshots to connect `Voice::Agent` to your own persistence and workflow layers.

## Voice Quality Checks

Use voice-focused RubyCritic checks for `lib/riffer/voice/**`:

```sh
# Generate JSON report in tmp/rubycritic-voice/report.json
bundle exec rake quality:voice:rubycritic

# Print modules below the minimum rating (default: B), non-blocking by default
bundle exec rake quality:voice:gate
```

Optional strict mode for local/CI experiments:

```sh
bundle exec rake quality:voice:gate RUBYCRITIC_ENFORCE=1 RUBYCRITIC_MIN_RATING=B
```

Interpretation:

- ratings are per module (`A` best, `F` worst)
- `quality:voice:gate` in default mode reports misses but does not fail the build
- when ready to enforce, set `RUBYCRITIC_ENFORCE=1` in CI

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
