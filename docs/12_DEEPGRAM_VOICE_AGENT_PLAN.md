# Deepgram Voice Agent Integration Plan

Date: 2026-03-04
Status: Proposed
Scope: Add first-class Deepgram Voice Agent support to `Riffer::Voice`, including tool-calling interoperability with `Riffer::Voice::Agent`.

## 1. Objectives

1. Add a new provider path `deepgram/<model>` to `Riffer::Voice.connect`.
2. Support Deepgram Voice Agent websocket session lifecycle with Riffer's existing runtime modes (`:auto`, `:async`, `:background`).
3. Preserve the existing public session API:
   - `send_audio_chunk(payload:, mime_type:)`
   - `send_text_turn(text:)`
   - `send_tool_response(call_id:, result:)`
   - `events` / `next_event`
4. Ensure Voice Agent tool calls map cleanly to `Riffer::Voice::Events::ToolCall` and can be auto-executed by `Riffer::Voice::Agent`.
5. Keep latency-sensitive behavior explicit (barge-in handling, turn completion, binary audio streaming).

## 2. Research Summary (Deepgram + article)

### 2.1 Voice Agent protocol essentials

Deepgram Voice Agent v1 uses:
- Endpoint: `wss://agent.deepgram.com/v1/agent/converse`
- Auth header: `Authorization` (`token <KEY>` or `bearer <JWT>`)
- Initial control message: `Settings`
- Duplex channel:
  - JSON control/events
  - binary audio frames (both inbound and outbound media)

### 2.2 Event model shape relevant to Riffer

Observed Deepgram events and mapping intent:

- `Welcome` -> internal readiness signal (optional metadata event)
- `SettingsApplied` -> successful setup confirmation
- `ConversationText` (`role`, `content`) ->
  - role `user` => `Riffer::Voice::Events::InputTranscript`
  - role `assistant` => `Riffer::Voice::Events::OutputTranscript`
- `UserStartedSpeaking` -> `Riffer::Voice::Events::Interrupt` (barge-in)
- `AgentAudioDone` -> `Riffer::Voice::Events::TurnComplete`
- binary audio frames -> `Riffer::Voice::Events::AudioChunk`
- `Error` / `Warning` -> `Riffer::Voice::Events::Error`

### 2.3 Tool-calling support findings

Deepgram Voice Agent supports tool/function calling natively via:

1. `agent.think.functions` in `Settings` and `UpdateThink`.
2. `FunctionCallRequest` server event with `functions` entries:
   - `id`
   - `name`
   - `arguments` (JSON string)
   - `client_side` boolean
3. `FunctionCallResponse` message from client when `client_side: true`:
   - `type: "FunctionCallResponse"`
   - `id`
   - `name`
   - `content` (string; often JSON-encoded data)
4. Server-side execution mode when `client_side: false` (server may emit `FunctionCallResponse` event).
5. Function-call context persistence via `agent.context.messages[*].function_calls` history.

### 2.4 Architecture takeaway from ntik article

The article emphasizes real-time orchestration fundamentals:
- immediate interruption propagation on user speech start,
- streaming pipeline overlap,
- and geographic co-location for latency.

This supports prioritizing Voice Agent path first (fewer moving parts), then optional Flux pipeline mode for advanced custom orchestration.

## 3. Recommended Implementation Strategy

## 3.1 Phase 1 (recommended now): Native Deepgram Voice Agent provider

Implement a new `deepgram` provider in the existing adapter/driver architecture.

Why first:
1. Closest fit to current `Riffer::Voice::Session` interface.
2. Least implementation risk for first shipped version.
3. Built-in function-calling protocol already exists and can map to current tool automation.

## 3.2 Phase 2 (optional): Flux transport mode

Add a separate composable mode (Flux STT + Riffer provider LLM + TTS) only after Phase 1, for teams needing full local orchestration control.

## 4. Detailed Work Plan

### WP1. Configuration and model resolution

Files:
- `lib/riffer/config.rb`
- `lib/riffer/voice/model_resolver.rb`
- tests for resolver/connect validation

Tasks:
1. Add `Deepgram = Struct.new(:api_key, keyword_init: true)`.
2. Expose `attr_reader :deepgram` and initialize it.
3. Extend `RESOLUTIONS` with:
   - provider: `"deepgram"`
   - adapter identifier: `:deepgram_voice_agent`
   - config key: `:deepgram`
4. Update validation error messaging to include `deepgram`.

Acceptance criteria:
- `Riffer::Voice.connect(model: "deepgram/...")` resolves adapter and enforces configured API key unless adapter injection is used.

### WP2. Adapter/driver registration

Files:
- `lib/riffer/voice/adapters/repository.rb`
- `lib/riffer/voice/drivers/repository.rb`
- new adapter and driver classes

Tasks:
1. Register `:deepgram_voice_agent` in both repositories.
2. Add `Riffer::Voice::Adapters::DeepgramVoiceAgent` mirroring current adapter pattern.
3. Add `Riffer::Voice::Drivers::DeepgramVoiceAgent` as provider-specific realtime driver.

Acceptance criteria:
- Repository lookup returns new classes.
- Adapter delegates full session contract to driver.

### WP3. Binary-capable transport contract

Files:
- `lib/riffer/voice/transports/async_websocket.rb`
- `lib/riffer/voice/transports/thread_websocket.rb`
- tests in `test/riffer/voice/transports/*`

Tasks:
1. Add `write_binary(payload)` in both transports.
2. Keep existing `write_json` behavior unchanged.
3. Ensure `read` can propagate binary frames as binary-compatible objects/strings.
4. Normalize frame extraction in driver runtime helper for binary vs JSON.

Acceptance criteria:
- Existing OpenAI/Gemini tests keep passing.
- New tests verify binary send and receive behavior.

### WP4. Deepgram protocol parser

Files:
- `lib/riffer/voice/parsers/deepgram_voice_agent_parser.rb`
- `lib/riffer/voice/parsers.rb`
- parser tests

Tasks:
1. Parse JSON events by `type`.
2. Convert `ConversationText` by role to `InputTranscript`/`OutputTranscript`.
3. Convert `FunctionCallRequest.functions[*]` to `ToolCall` events:
   - `call_id <- id`
   - `name <- name`
   - `arguments <- JSON.parse(arguments)` with safe fallback `{}`.
4. Convert `UserStartedSpeaking` to `Interrupt`.
5. Convert `AgentAudioDone` to `TurnComplete`.
6. Convert `Error`/`Warning` to `Error` events (with `retriable` policy).

Acceptance criteria:
- Parser test suite covers happy path and malformed arguments.
- No parser exception escapes for invalid function argument JSON.

### WP5. Driver lifecycle and handshake

Files:
- `lib/riffer/voice/drivers/deepgram_voice_agent.rb`
- split modules under `lib/riffer/voice/drivers/deepgram_voice_agent_*`
- driver tests

Tasks:
1. Validate API key and model.
2. Connect to Deepgram endpoint with auth header.
3. Send `Settings` payload on connect.
4. Start read loop and route JSON vs binary frames.
5. Emit parsed events via callback hooks.
6. Support clean idempotent close and read-loop teardown.

Acceptance criteria:
- Emits connect errors using `emit_error` and re-raises root cause.
- `connected?`, `close`, and cleanup semantics match existing drivers.

### WP6. Outbound dispatch mapping

Files:
- `lib/riffer/voice/drivers/deepgram_voice_agent_dispatch.rb`
- driver tests

Tasks:
1. `send_audio_chunk`:
   - accept current Riffer base64 payload contract
   - decode base64
   - send binary media frame via `write_binary`
2. `send_text_turn`:
   - map to `InjectUserMessage`
3. `send_tool_response`:
   - map to `FunctionCallResponse`
   - `id <- call_id`
   - `content <- string or JSON.stringify(result)`

Acceptance criteria:
- Invalid payloads are no-op or error-consistent with existing drivers.
- Transport writes match Deepgram message format.

### WP7. Tool-calling interoperability policy

Files:
- parser + driver + docs + tests

Tasks:
1. Client-side function execution path:
   - on `FunctionCallRequest` with `client_side: true`, emit `ToolCall`.
   - `Riffer::Voice::Agent` auto-handles and calls `send_tool_response`.
2. Server-side function path:
   - on `client_side: false`, do not emit executable `ToolCall`.
   - optionally emit metadata-only event in `OutputTranscript` or ignore.
3. Handle server-emitted `FunctionCallResponse` event:
   - parse and attach to metadata stream (optional), avoid duplicate tool execution.
4. Preserve compatibility with current `ToolCall` contract where `arguments` must be Hash.

Acceptance criteria:
- No double execution for server-side calls.
- Auto tool execution works out-of-the-box for client-side calls.

### WP8. Documentation and examples

Files:
- `docs/10_REALTIME_VOICE.md`
- `docs_providers/` (new Deepgram voice doc)
- optional `examples/voice/*`

Tasks:
1. Add setup section for `Riffer.config.deepgram.api_key`.
2. Document Deepgram model format examples.
3. Add tool-calling example with `FunctionCallRequest` flow.
4. Document binary audio behavior and MIME expectations.

Acceptance criteria:
- User can run a minimal Deepgram voice session from docs.

## 5. Testing Plan

## 5.1 Unit tests

- `test/riffer/voice/model_resolver_test.rb` update for deepgram.
- new adapter tests: `test/riffer/voice/adapters/deepgram_voice_agent_test.rb`.
- new driver tests: `test/riffer/voice/drivers/deepgram_voice_agent_test.rb`.
- new parser tests: `test/riffer/voice/parsers/deepgram_voice_agent_parser_test.rb`.
- transport tests expanded for `write_binary` and mixed frame handling.

## 5.2 Integration-style behavior tests

Using fake transport/task helpers, verify:
1. connect handshake (`Settings` first)
2. event mapping for text/interrupt/audio done
3. function call request -> tool response round-trip
4. barge-in behavior (`UserStartedSpeaking` while audio is being emitted)
5. close idempotency and reader-loop shutdown

## 5.3 Regression gates

- `bundle exec rake`
- ensure all current OpenAI/Gemini voice tests remain green
- add strict parser robustness checks for malformed JSON/function args

## 6. Risks and Mitigations

1. Binary transport compatibility risk
- Risk: websocket gems differ in binary send/receive semantics.
- Mitigation: isolate binary writes in transport layer + exhaustive fake transport tests.

2. Function-call semantic mismatch
- Risk: Deepgram server-side function execution (`client_side: false`) could trigger incorrect local tool execution.
- Mitigation: gate tool event emission strictly on `client_side: true`.

3. Event ordering race conditions
- Risk: `AgentAudioDone` may arrive before playback drains locally.
- Mitigation: keep event semantic as "server finished sending", document playback caveat.

4. Context inflation with function payloads
- Risk: long JSON function arguments/responses increase context and latency.
- Mitigation: recommend concise `FunctionCallResponse.content` and optional summarization strategy.

## 7. Milestones and Exit Criteria

Milestone A: Protocol foundation
- WP1-WP4 complete.
- All parser + transport tests green.

Milestone B: End-to-end session
- WP5-WP6 complete.
- Deepgram session works for text + audio + turn complete + interrupt.

Milestone C: Tool-calling ready
- WP7 complete.
- `Riffer::Voice::Agent` auto tool execution verified on client-side function calls.

Milestone D: Production readiness
- WP8 complete.
- Documentation and examples published.
- Full `bundle exec rake` passing.

## 8. Proposed Task Ordering

1. WP1
2. WP2
3. WP3
4. WP4
5. WP5
6. WP6
7. WP7
8. WP8

Rationale: build config + protocol + transport first, then lifecycle, then function-calling guarantees, then docs.

## 9. Appendix: Tool-Calling Mapping Spec (Riffer <-> Deepgram)

Inbound Deepgram -> Riffer
- `FunctionCallRequest.functions[n].id` -> `ToolCall#call_id`
- `FunctionCallRequest.functions[n].name` -> `ToolCall#name`
- `FunctionCallRequest.functions[n].arguments` (JSON string) -> `ToolCall#arguments` (Hash)
- `FunctionCallRequest.functions[n].client_side`
  - `true` -> emit `ToolCall`
  - `false` -> no executable `ToolCall` emission

Outbound Riffer -> Deepgram
- `send_tool_response(call_id:, result:)` ->
  - `{"type":"FunctionCallResponse","id":call_id,"name":tool_name?,"content":serialized_result}`

Serialization rule
- String result: pass-through
- Non-string result: JSON encode
- Error result from `Riffer::Tools::Response.error`: JSON object string with error details

## 10. Sources

- https://www.ntik.me/posts/voice-agent
- https://developers.deepgram.com/docs/configure-voice-agent
- https://developers.deepgram.com/docs/voice-agents-function-calling
- https://developers.deepgram.com/docs/voice-agent-function-call-request
- https://developers.deepgram.com/docs/voice-agent-function-call-response
- https://developers.deepgram.com/docs/voice-agent-history
- https://developers.deepgram.com/docs/voice-agent-outputs
- https://developers.deepgram.com/docs/voice-agent-update-think
- https://developers.deepgram.com/docs/voice-agent-conversation-text
- https://developers.deepgram.com/docs/voice-agent-user-started-speaking
- https://developers.deepgram.com/docs/voice-agent-agent-audio-done
- https://developers.deepgram.com/reference/voice-agent/voice-agent
- https://developers.deepgram.com/docs/flux/agent
