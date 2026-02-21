# Realtime Voice Plan (Fiber-First, Driver-Only v1)

## Scope
Add an additive `Riffer::Voice` subsystem to support provider-neutral realtime voice drivers in riffer.

v1 includes:

- `Riffer::Voice::Drivers` contract
- typed realtime voice events
- driver registry
- Gemini Live driver
- OpenAI Realtime GA driver

v1 excludes:

- session runtime helper in riffer
- telephony adapters (Telnyx/Twilio/WebRTC)
- app-level orchestration/workflow policy

## Goals

1. Standardize realtime STS abstraction for consumer apps (`voice_inteligence`, `jane`).
2. Preserve host app ownership of orchestration and tool execution.
3. Support Gemini and OpenAI under one consistent API.
4. Keep all existing text-provider and `Riffer::Agent` flows backward compatible.

## Public API

### Namespaces

- `Riffer::Voice`
- `Riffer::Voice::Drivers`
- `Riffer::Voice::Events`
- `Riffer::Voice::Parsers`
- `Riffer::Voice::Transports`

### Driver contract

```ruby
class Riffer::Voice::Drivers::Base
  def connect(system_prompt:, tools: [], config: {}, callbacks: {}); end
  def connected?; end
  def send_audio_chunk(payload:, mime_type:); end
  def send_text_turn(text:, role: "user"); end
  def send_tool_response(call_id:, result:); end
  def close(reason: nil); end
end
```

### Callback contract

Supported callback keys in `callbacks`:

- `on_event`
- `on_audio_chunk`
- `on_input_transcript`
- `on_output_transcript`
- `on_tool_call`
- `on_interrupt`
- `on_turn_complete`
- `on_usage`
- `on_error`

All callbacks are optional and default to no-op.

### Typed events

- `Riffer::Voice::Events::AudioChunk`
- `Riffer::Voice::Events::InputTranscript`
- `Riffer::Voice::Events::OutputTranscript`
- `Riffer::Voice::Events::ToolCall`
- `Riffer::Voice::Events::Interrupt`
- `Riffer::Voice::Events::TurnComplete`
- `Riffer::Voice::Events::Usage`
- `Riffer::Voice::Events::Error`

### Driver registry

```ruby
Riffer::Voice::Drivers::Repository.find(:gemini_live)
Riffer::Voice::Drivers::Repository.find(:openai_realtime)
```

## Concurrency model

1. Fiber-based runtime only (`async`, `async-http`, `async-websocket`).
2. No thread creation and no thread synchronization primitives in voice subsystem code.
3. Driver `connect` requires active Async task context and fails fast with actionable error if absent.
4. `close` is idempotent.

## Tool execution model

Tool execution remains in the host app:

- driver emits `ToolCall` events
- host runs tool logic
- host returns output with `send_tool_response`

## Provider mapping

### Gemini Live (`:gemini_live`)

Connect/setup:

- websocket to Gemini Live endpoint with API key query parameter
- send setup payload with model, system prompt, tools, config

Inbound mapping:

- inline audio -> `AudioChunk`
- input transcription -> `InputTranscript`
- output transcription -> `OutputTranscript`
- tool call payload -> `ToolCall`
- interruption signal -> `Interrupt`
- turn complete signal -> `TurnComplete`
- usage metadata -> `Usage`

Outbound mapping:

- audio chunk -> realtime input audio payload
- text turn -> client content turn with `turnComplete: true`
- tool response -> Gemini `toolResponse.functionResponses`

### OpenAI Realtime GA (`:openai_realtime`)

Connect/setup:

- websocket to OpenAI realtime endpoint with `?model=`
- bearer auth header
- initial `session.update` with instructions/tools/config

Inbound mapping:

- `response.output_audio.delta` -> `AudioChunk`
- input audio transcription events -> `InputTranscript`
- output transcript delta/done events -> `OutputTranscript`
- `response.function_call_arguments.done` -> `ToolCall`
- interruption/speech-start style events -> `Interrupt`
- `response.done` usage -> `Usage`
- error payload -> `Error`

Outbound mapping:

- audio -> `input_audio_buffer.append`
- text -> `conversation.item.create` input text item
- tool response -> `function_call_output` item + `response.create`

Policy:

- GA model only in v1
- no OpenAI beta realtime compatibility layer

## Delivery phases

### Phase 1: Contracts and events

- namespaces and base classes
- event objects + `to_h`
- repository registration
- tests and RBS generation

### Phase 2: Shared transport and parsers

- async websocket transport adapter
- Gemini/OpenAI parser normalization
- malformed payload tolerance tests

### Phase 3: Gemini driver

- connect/read/write/close
- event emission
- test coverage for happy path and error path

### Phase 4: OpenAI driver

- GA realtime protocol handling
- tool response plumbing
- parity tests with shared callback model

### Phase 5: Consumer adoption

- `voice_inteligence` adapter integration
- `jane` adapter integration
- gradual migration with parity verification

### Phase 6: Docs and release

- docs pages and examples
- changelog update
- final migration notes

## Test matrix

1. Event object tests:
- field readers
- `to_h` shape

2. Repository tests:
- registered drivers resolve
- unknown key returns `nil`

3. Parser tests:
- canonical payload mapping for Gemini/OpenAI
- malformed JSON/unknown fields tolerance

4. Driver tests:
- connect success
- send audio/text/tool response payloads
- callback dispatch and callback error capture
- idempotent close
- async-context validation

5. Regression gate:
- full `bundle exec rake` must pass.

## Risks and mitigations

1. Provider protocol drift:
- isolate provider-specific mapping in parser layer.

2. Audio format mismatch:
- keep explicit `mime_type` in API and events.

3. Callback exceptions:
- catch callback errors and emit structured `Error` events.

4. Host runtime misuse:
- fail fast when Async task context is missing.

## Assumptions and defaults

1. Host app owns orchestration and tool execution.
2. Telephony remains outside riffer.
3. Default payload format is base64 audio with provider-specific MIME.
4. Existing riffer APIs remain additive and non-breaking.

## Quality bar

Before any phase transition:

- targeted tests for the phase pass
- standard linting passes
- full `bundle exec rake` passes
