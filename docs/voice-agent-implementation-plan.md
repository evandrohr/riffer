# Voice Agent Implementation Plan

Date: 2026-02-28  
Owner: Riffer maintainers  
Status: Planned

## Objective

Fully implement `Riffer::Voice::Agent` as the high-level realtime orchestration layer on top of `Riffer::Voice::Session`, with strong Riffer DX, provider neutrality, and production-grade tool execution behavior.

This plan intentionally keeps `Riffer::Voice::Session` as the transport/lifecycle primitive and adds orchestration as a separate element.

## Inputs Considered

- Current `riffer` voice architecture and DX constraints.
- Proven orchestration patterns extracted from `../voice_inteligence`.
- Architecture inspiration from Notion page `Jane.ai — Agent Jane Architecture` (fetched via Notion MCP), selectively applied.

## Notion-Inspired Opportunities Selected

These are the low-hanging patterns that fit Riffer core:

- Role/profile-driven runtime configuration (single agent, different runtime "suits").
- Small, semantically clear operation entry points (`read` vs `perform`) as an optional tooling pattern.
- Dispatch-time policy enforcement (validation, risk tier handling, action budgets, approval hooks).
- Structured, recoverable error payloads from tool execution.
- Lightweight durability hooks for checkpoint/resume integration by apps.

## Explicitly Deferred (Out of Riffer Core Scope)

These are intentionally not part of this plan:

- Cortex-style authoring service (skills/roles GUI, publish pipeline).
- Monolith/Cortex sync architecture.
- Memory block storage/retrieval lifecycle.
- Telephony/voice transport adapters with business workflows.
- Domain-specific operation registries for healthcare or any vertical.

## Guiding Principles (DX + Architecture)

- Keep the mental model simple:
  - `Riffer::Voice::Session` = low-level send/receive lifecycle.
  - `Riffer::Voice::Agent` = orchestration + tool handling convenience.
- Preserve additive compatibility:
  - Existing `Riffer::Voice.connect` usage continues to work unchanged.
- Mirror familiar Riffer patterns:
  - class-level DSL (`model`, `instructions`, `uses_tools`)
  - sensible defaults, explicit overrides
  - strict input validation and typed events
- Avoid app/domain concerns in core:
  - no telephony adapters, no persistence engines, no vertical business contracts.
- Keep provider behavior normalized:
  - execution semantics should not depend on OpenAI vs Gemini quirks.

## Current State Snapshot

Already implemented:

- `Riffer::Voice::Session` with event queue and runtime handling.
- `Riffer::Voice::Agent` baseline:
  - DSL (`model`, `instructions`, `uses_tools`)
  - `connect`, `events`, `next_event`, `send_*`, `close`
  - automatic `ToolCall` execution using `Riffer::Tool#call_with_validation`
  - structured tool error payload serialization
- Initial docs and tests.

Gaps to close for "full implementation":

- callback ergonomics and event-router API.
- explicit run helpers for common loops.
- configurable tool execution strategy and hooks.
- role/profile runtime configuration.
- policy gates and operation budgets.
- durability hooks for app-managed resume.
- broader test coverage and migration docs.

## Scope

In scope:

- Voice Agent orchestration ergonomics.
- Tool execution policy and hooks.
- Event handling and run-loop utilities.
- Interrupt/error semantics and deterministic lifecycle.
- Role/profile runtime abstraction.
- Optional operation-dispatch toolkit (`read` / `perform` pattern).
- Lightweight durability hooks (not storage).
- Documentation + migration guidance.
- Comprehensive automated tests.

Out of scope:

- Telephony integrations (Telnyx/Twilio).
- Built-in persistent task engines or workflow schedulers.
- Domain-specific operation catalogs or policy engines.
- Skill-authoring products and data planes.
- Replacing text `Riffer::Agent`.

## Target Public DX (End State)

```ruby
class SupportVoiceAgent < Riffer::Voice::Agent
  model "openai/gpt-realtime-1.5"
  instructions "You are a concise support assistant."
  uses_tools [LookupAccountTool, CreateTicketTool]

  profile :receptionist do
    runtime :auto
    auto_handle_tool_calls true
    action_budget max_mutations: 3
  end
end

agent = SupportVoiceAgent.connect(
  profile: :receptionist,
  tool_context: {account_id: "acct_123"}
)

agent.on_tool_call { |event| puts event.name }
agent.run_until_turn_complete(text: "Help me reset my password")
agent.close
```

## Workstreams

## 1) API + DSL Hardening

Goal: finalize a stable, explicit API contract for `Riffer::Voice::Agent`.

Tasks:

- Add class-level options for:
  - default runtime mode
  - default auto tool handling behavior
  - default voice config payload
- Add instance-level override precedence rules and document them.
- Add explicit validation errors for missing/invalid configuration.
- Add parity convenience constructors:
  - `.connect(...)`
  - `.new(...).connect(...)`

Potential files:

- `lib/riffer/voice/agent.rb`
- `docs/10_REALTIME_VOICE.md`

Tests:

- `test/riffer/voice/agent_test.rb`

Acceptance criteria:

- No ambiguous precedence between class DSL and runtime overrides.
- Misconfiguration failures are actionable and deterministic.

## 2) Event Router + Callback Registry (Low-Hanging Fruit)

Goal: provide ergonomic event handling inspired by app-level callback mapping, without leaking app payload contracts into core.

Tasks:

- Add callback registration methods:
  - `on_event`
  - `on_audio_chunk`
  - `on_input_transcript`
  - `on_output_transcript`
  - `on_tool_call`
  - `on_interrupt`
  - `on_turn_complete`
  - `on_usage`
  - `on_error`
- Ensure callbacks receive normalized `Riffer::Voice::Events::*`.
- Guard callback failures with a documented policy.

Potential files:

- `lib/riffer/voice/agent.rb`

Tests:

- callback-focused tests in `test/riffer/voice/agent_test.rb`

Acceptance criteria:

- Callback API works in both `events` iteration and run-helper methods.
- Callback exceptions follow documented behavior (no silent drops).

## 3) Tool Execution Pipeline + Hooks

Goal: make automatic tool handling extensible while preserving safe defaults.

Tasks:

- Introduce injectable tool executor strategy:
  - default: existing `Riffer::Tool` class execution.
  - custom: callable hook for advanced environments.
- Add lifecycle hooks:
  - before tool execution
  - after tool execution
  - on tool execution error
- Add deterministic serialization policy:
  - success response
  - error response with stable fields.
- Define explicit behavior for raw schema-hash tools (non-class declarations).

Potential files:

- `lib/riffer/voice/agent.rb`
- optional helper classes under `lib/riffer/voice/agent/`

Tests:

- extend `test/riffer/voice/agent_test.rb` for hooks/injection paths.

Acceptance criteria:

- Default path requires no extra configuration.
- Advanced path supports external execution cleanly.

## 4) Role Profiles (Notion-Inspired, Scoped)

Goal: support one agent class with different runtime profiles (role-like config bundles).

Tasks:

- Add profile DSL to `Riffer::Voice::Agent` for named config bundles:
  - model override
  - instructions override
  - tools set
  - runtime/config defaults
  - safety defaults (budget/policy knobs)
- Add `connect(profile: ...)` resolution and validation.
- Keep profiles optional; existing behavior remains default.

Potential files:

- `lib/riffer/voice/agent.rb`
- docs updates in `docs/10_REALTIME_VOICE.md`

Tests:

- profile resolution tests in `test/riffer/voice/agent_test.rb`

Acceptance criteria:

- One class can represent multiple surface modes without subclass explosion.
- Profile behavior is deterministic and documented.

## 5) Policy Gates + Action Budgets (Notion-Inspired, Low-Hanging Fruit)

Goal: add defense-in-depth primitives at dispatch time without building a full policy platform.

Tasks:

- Add optional mutation policy hook at tool-dispatch time.
- Add optional action budget counters per session:
  - max tool calls
  - max mutation-class tool calls (user-defined classifier hook)
- Add approval callback hook for gated operations.
- Emit structured policy errors in tool responses.

Potential files:

- `lib/riffer/voice/agent.rb`
- optional new policy helper classes under `lib/riffer/voice/agent/`

Tests:

- policy/budget tests in `test/riffer/voice/agent_test.rb`

Acceptance criteria:

- Policy violations are deterministic, typed, and recoverable.
- Apps can plug in governance without forking Voice Agent.

## 6) Run Helpers + Lifecycle Semantics

Goal: reduce boilerplate loops for common voice workflows.

Tasks:

- Add helper methods such as:
  - `run_loop(timeout:)`
  - `run_until_turn_complete(...)`
  - `drain_available_events(max_events:)`
- Ensure helpers preserve session fail-fast semantics.
- Define stop conditions clearly:
  - disconnection
  - explicit close
  - interrupt events
  - timeout boundaries.

Potential files:

- `lib/riffer/voice/agent.rb`
- `docs/10_REALTIME_VOICE.md`

Tests:

- helper behavior tests in `test/riffer/voice/agent_test.rb`

Acceptance criteria:

- Common app loops can be replaced by one helper call.
- No hidden background threads/tasks introduced by default.

## 7) Durability Hooks (Notion-Inspired, Scoped)

Goal: provide app-friendly hooks for durable execution/resume without implementing a workflow engine in Riffer.

Tasks:

- Add optional event callbacks for checkpoint points:
  - turn complete
  - tool request sent
  - tool response sent
  - recoverable error
- Add lightweight state snapshot export/import helpers for agent-side metadata only (not provider transport state).
- Document app-managed resume contract.

Potential files:

- `lib/riffer/voice/agent.rb`
- docs in `docs/10_REALTIME_VOICE.md`

Tests:

- snapshot/hook behavior tests in `test/riffer/voice/agent_test.rb`

Acceptance criteria:

- Apps can wire durable jobs around Voice Agent without monkey patches.
- Riffer remains storage-agnostic.

## 8) Documentation + Migration Notes

Goal: make adoption straightforward for existing `Riffer::Voice.connect` and app-level orchestration users.

Tasks:

- Add dedicated sections in `docs/10_REALTIME_VOICE.md`:
  - "When to use Session vs Voice::Agent"
  - callback patterns
  - profiles
  - policy hooks
  - durability hooks
- Add migration snippets from manual `session.next_event` loops.
- Keep docs explicit that telephony/persistence/authoring planes remain app responsibilities.

Potential files:

- `docs/10_REALTIME_VOICE.md`
- `docs/02_GETTING_STARTED.md`
- optional `examples/` additions for voice-agent usage

Acceptance criteria:

- Readers can adopt Voice Agent without reading internals.
- Boundary between framework and app responsibilities is explicit.

## 9) Test Matrix + Quality Gates

Goal: guarantee behavior consistency across runtime modes and execution paths.

Tests to add/expand:

- Runtime matrix:
  - `:background`
  - `:async` (within Async task context)
- Tool execution matrix:
  - success
  - unknown tool
  - validation error
  - timeout
  - execution exception
  - custom executor
- Profile/policy matrix:
  - profile overrides
  - budget exhaustion
  - approval required/denied
- Durability hooks matrix:
  - snapshot export/import
  - checkpoint callbacks

Quality gates:

- `bundle exec rake standard`
- targeted voice tests + full suite (`bundle exec rake`)

## Rollout Sequence

1. API hardening + callbacks (Workstreams 1 and 2).
2. Tool pipeline extensibility (Workstream 3).
3. Profiles + policy gates (Workstreams 4 and 5).
4. Helpers + durability hooks (Workstreams 6 and 7).
5. Docs + final QA (Workstreams 8 and 9).

## Risks and Mitigations

- Risk: overfitting Voice Agent to one app orchestration shape.
  - Mitigation: keep callback payloads as core typed events, not app-specific hashes.
- Risk: hidden complexity harms DX.
  - Mitigation: default path remains `connect + events + optional auto tools`.
- Risk: policy/budget hooks become pseudo-domain logic.
  - Mitigation: provide generic interfaces only; caller defines classification/policy.
- Risk: durability expectations creep into storage concerns.
  - Mitigation: expose hooks and snapshot helpers only; no persistence implementation.

## Deliverables

- Expanded `Riffer::Voice::Agent` with stable orchestration API.
- Profile and policy primitives that remain framework-generic.
- Durability integration hooks for app-managed resume.
- Updated voice docs with migration and usage guidance.
- Comprehensive voice-agent test coverage.
- Follow-up tracker document for execution accountability.
