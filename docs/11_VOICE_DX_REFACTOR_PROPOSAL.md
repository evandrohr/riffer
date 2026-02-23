# Voice DX Refactor Proposal

## Status
- Proposed
- Date: 2026-02-23
- Compatibility: Breaking change accepted

## Execution Documents
- Detailed phased plan: `docs/12_VOICE_IMPLEMENTATION_PLAN.md`
- Pause/resume follow-up tracker: `docs/13_VOICE_IMPLEMENTATION_FOLLOW_UP.md`

## Summary
This proposal replaces the current voice surface with a single native Riffer API that:

- works with and without caller-managed Async context
- uses `provider/model` model selection
- exposes enumerable typed events instead of callback-first wiring

This is a clean-slate implementation. Legacy voice APIs are removed from public usage.

## Motivation
Current voice support diverges from established gem ergonomics:

- Async task context is mandatory at call sites
- callback wiring is primary
- model/provider selection differs from `Riffer::Agent`
- tool-call argument format is inconsistent (`String` vs `Hash`)

The new design optimizes for native Riffer DX, not compatibility with the previous voice API.

## Design Goals
1. One obvious public entry point for voice sessions.
2. Unified runtime behavior in both Async and non-Async environments.
3. `provider/model` parity with `Riffer::Agent`.
4. Stable typed event contract with normalized tool-call arguments.
5. No parallel legacy API surface to maintain.

## Non-Goals
- Building full `Riffer::Agent` voice orchestration in this phase.
- Supporting old driver-first integration patterns.
- Maintaining old voice docs/examples/API aliases.

## Proposed Public API
```ruby
session = Riffer::Voice.connect(
  model: "openai/gpt-realtime",
  system_prompt: "You are a concise voice assistant.",
  tools: [MyTool],
  config: {temperature: 0.2},
  runtime: :auto # :auto, :async, :background
)

session.send_text_turn(text: "Say hello.")

session.events.each do |event|
  case event
  when Riffer::Voice::Events::OutputTranscript
    puts event.text
  when Riffer::Voice::Events::ToolCall
    result = MyTool.new.call(context: nil, **event.arguments_hash)
    session.send_tool_response(call_id: event.call_id, result: result)
  when Riffer::Voice::Events::TurnComplete
    break
  end
end

session.close
```

Convenience pull API:

```ruby
event = session.next_event(timeout: 5)
```

## Runtime Behavior (With and Without Async)
### `runtime: :auto` (default)
- If Async task exists, use it.
- Otherwise run an internal background Async reactor.

### `runtime: :async`
- Require active Async task.
- Raise `Riffer::ArgumentError` if missing.

### `runtime: :background`
- Always use internal background reactor.
- Caller never needs `Async do ... end`.

## Architecture
### Public
- `Riffer::Voice.connect`
- `Riffer::Voice::Session`
- `Riffer::Voice::Events::*`

### Internal
- `Riffer::Voice::Runtime::Resolver`
- `Riffer::Voice::Runtime::ManagedAsync`
- `Riffer::Voice::Runtime::BackgroundAsync`
- `Riffer::Voice::EventQueue`
- `Riffer::Voice::ModelResolver`
- provider adapters (OpenAI realtime, Gemini live)

Adapters stay internal implementation details. They are not part of the supported public API.

## Model Resolution
Only `provider/model` format is supported:

- `openai/gpt-realtime` -> OpenAI realtime adapter
- `gemini/gemini-2.5-flash-native-audio-preview-12-2025` -> Gemini live adapter

Legacy forms such as `openai_realtime/*` and `gemini_live/*` are removed.

## Event and Tool Call Contract
`Riffer::Voice::Events::ToolCall` is normalized:

- `arguments` is always a `Hash[String, untyped]`
- `arguments_hash` remains as explicit convenience alias

No caller branching for raw JSON strings.

## Error Model
- `Riffer::Voice.connect(...)` raises on setup/config/runtime bootstrap failures.
- runtime/provider failures emit `Riffer::Voice::Events::Error`.
- invalid lifecycle operations (`closed`, `not connected`) raise `Riffer::Error`.

## Breaking Changes
1. Remove public use of `Riffer::Voice::Drivers::*`.
2. Remove callback-first `connect(..., callbacks: ...)` contract.
3. Remove requirement for caller-owned Async runtime in default flow.
4. Remove legacy voice model aliases.
5. Remove tool-call `String | Hash` argument union from public event contract.
6. Replace top-level voice docs and examples with session-first API only.

## Implementation Plan
### Phase 1: New Session Core
- Implement `Riffer::Voice.connect` and `Riffer::Voice::Session`.
- Implement runtime resolver and both runtime modes.
- Add event queue and `events`/`next_event`.

### Phase 2: Provider Adapters
- Port existing OpenAI/Gemini realtime behavior into internal adapters.
- Wire adapters to normalized event contract.

### Phase 3: Model Resolver + Validation
- Enforce `provider/model` parsing.
- Add strict validation and actionable errors.

### Phase 4: Docs + Surface Cutover
- Rewrite `docs/10_REALTIME_VOICE.md` around new API.
- Remove references to old public driver usage from docs.
- Update overview/getting-started links/examples.

### Phase 5: Deletion
- Remove obsolete public voice entry points and tests tied to old contract.

## Testing Strategy
1. Session lifecycle tests (`connect`, send, receive, `close`).
2. Runtime matrix tests (`:auto`, `:async`, `:background`).
3. Adapter integration tests for OpenAI and Gemini behavior parity.
4. Event contract tests, especially normalized tool-call arguments.
5. Failure-path tests for setup/bootstrap/runtime/lifecycle errors.

## Migration
This is a breaking cutover. Existing voice integrations must move to:

- `Riffer::Voice.connect(...)`
- `session.events` or `session.next_event(...)`
- `provider/model` voice model names

No compatibility shim is planned.

## Acceptance Criteria
1. Voice can run from plain Ruby without `Async do ... end`.
2. Voice can run inside existing Async task context.
3. Only one public API path exists for voice sessions.
4. Voice model selection uses only `provider/model`.
5. Tool-call arguments are normalized and branch-free for callers.
6. Public docs show only the new API.

## Risks and Mitigations
- Risk: migration burden for early adopters.
  - Mitigation: clear migration section and direct before/after examples.

- Risk: runtime complexity in background mode.
  - Mitigation: strict ownership/lifecycle tests and deterministic teardown.

- Risk: hidden dependency on old callbacks in user code.
  - Mitigation: explicit breaking-change callouts in changelog and docs.

## Open Questions
1. Should `session.events` be infinite until explicit close, or auto-stop on `TurnComplete`?
2. Should automatic tool execution be part of this phase (`Riffer::Voice::ToolRunner`)?
3. Should adapter classes remain internal constants or private implementation files only?
