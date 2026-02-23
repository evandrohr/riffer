# Voice RFC Implementation Plan (Phased)

## Status
- Drafted: 2026-02-23
- Source RFC: `docs/11_VOICE_DX_REFACTOR_PROPOSAL.md`
- Compatibility mode: Breaking change (no legacy shim)

## Goal
Implement the new voice architecture defined in the RFC with:

- one public API (`Riffer::Voice.connect` + `Riffer::Voice::Session`)
- runtime support for both Async and non-Async callers
- strict `provider/model` voice model resolution
- normalized tool-call event contract
- full docs/test cutover to the new surface

## Delivery Strategy
- Implement in small, mergeable phases with strict exit criteria.
- Keep each phase independently testable.
- Use hard phase gates to avoid carrying unstable behavior forward.
- Maintain a dedicated follow-up tracker while implementation is in progress:
  `docs/13_VOICE_IMPLEMENTATION_FOLLOW_UP.md`

## Phase Map

| Phase | Name | Primary Output | Stop-Safe |
| --- | --- | --- | --- |
| 0 | Kickoff + Baseline | PR-branch baseline checks | yes |
| 1 | Session API Skeleton | `Riffer::Voice.connect` + `Session` scaffold | yes |
| 2 | Runtime Layer | `:auto`, `:async`, `:background` runtime execution | yes |
| 3 | Event Queue + Stream API | `events` enumerator + `next_event` timeout API | yes |
| 4 | Internal Provider Adapters | OpenAI + Gemini adapters under internal namespace | yes |
| 5 | Model Resolver + Validation | strict `provider/model` mapping and errors | yes |
| 6 | Event Contract Normalization | normalized `ToolCall` arguments hash contract | yes |
| 7 | Public Surface Cutover | remove old public voice entry points/docs usage | yes |
| 8 | Hardening + Release Prep | full tests, changelog, migration notes | yes |

## Detailed Phase Plan

## Phase 0: Kickoff + Baseline
Objective:
- freeze baseline and ensure deterministic local verification path.

Tasks:
- confirm work will continue on the current PR branch (no branch split).
- run baseline tests for voice and capture output.
- record environment assumptions in follow-up file.
- identify any pre-existing repo changes that may affect voice work.

Verification gate:
- baseline voice tests pass.
- follow-up file initialized with current PR branch metadata and baseline test result.

Exit criteria:
- Phase 0 checklist complete in follow-up file.

## Phase 1: Session API Skeleton
Objective:
- establish the new public API skeleton without provider integration.

Tasks:
- add `Riffer::Voice.connect(...)`.
- add `Riffer::Voice::Session` with lifecycle methods:
  `send_text_turn`, `send_audio_chunk`, `send_tool_response`, `events`, `next_event`, `close`.
- add lifecycle state guards (`connected`, `closed`).
- define expected constructor/input validation behavior.

Likely files:
- `lib/riffer/voice.rb`
- `lib/riffer/voice/session.rb`
- `sig/generated/riffer/voice/session.rbs` (or generated equivalent)
- `test/riffer/voice/session_test.rb`

Verification gate:
- new session tests pass for skeleton lifecycle and input validation.

Exit criteria:
- public API compiles, tests green, no runtime wiring yet.

## Phase 2: Runtime Layer
Objective:
- support execution in both caller-managed Async and non-Async contexts.

Tasks:
- implement `Riffer::Voice::Runtime::Resolver`.
- implement `Riffer::Voice::Runtime::ManagedAsync`.
- implement `Riffer::Voice::Runtime::BackgroundAsync`.
- wire `runtime: :auto | :async | :background` selection in `Voice.connect`.
- enforce `:async` behavior when no Async task exists.

Likely files:
- `lib/riffer/voice/runtime/resolver.rb`
- `lib/riffer/voice/runtime/managed_async.rb`
- `lib/riffer/voice/runtime/background_async.rb`
- `lib/riffer/voice/runtime.rb`
- `test/riffer/voice/runtime/*`

Verification gate:
- runtime-mode matrix tests pass.

Exit criteria:
- deterministic runtime behavior with explicit mode tests.

## Phase 3: Event Queue + Stream API
Objective:
- provide stable event consumption APIs independent of provider implementation.

Tasks:
- implement thread-safe event queue (`push`, `close`, `pop(timeout:)`).
- implement `session.events` enumerator behavior.
- implement `session.next_event(timeout:)`.
- define end-of-stream semantics.

Likely files:
- `lib/riffer/voice/event_queue.rb`
- `test/riffer/voice/event_queue_test.rb`
- `test/riffer/voice/session_events_test.rb`

Verification gate:
- queue/timeout/enumerator tests pass in both runtime modes.

Exit criteria:
- event pipeline stable before provider adapter integration.

## Phase 4: Internal Provider Adapters
Objective:
- connect session/runtime to provider-specific realtime behavior through internal adapters.

Tasks:
- add internal OpenAI realtime adapter.
- add internal Gemini live adapter.
- integrate existing parser logic or equivalent behavior.
- route adapter outputs into `EventQueue`.
- route session send methods to adapter operations.

Likely files:
- `lib/riffer/voice/adapters/openai_realtime.rb`
- `lib/riffer/voice/adapters/gemini_live.rb`
- `lib/riffer/voice/adapters/base.rb`
- `lib/riffer/voice/adapters.rb`
- adapter integration tests

Verification gate:
- adapter integration tests produce expected typed events.
- lifecycle behavior (`connect`/`close`) deterministic across adapters.

Exit criteria:
- session works end-to-end for both providers.

## Phase 5: Model Resolver + Validation
Objective:
- enforce only `provider/model` input and strict provider mapping.

Tasks:
- implement `Riffer::Voice::ModelResolver`.
- map supported providers (`openai`, `gemini`) to internal adapters.
- reject legacy model prefixes and invalid strings with explicit errors.
- validate required config availability for selected provider.

Likely files:
- `lib/riffer/voice/model_resolver.rb`
- `test/riffer/voice/model_resolver_test.rb`
- `test/riffer/voice/connect_validation_test.rb`

Verification gate:
- invalid model inputs fail with actionable messages.
- valid models resolve correctly.

Exit criteria:
- model resolution locked to RFC behavior.

## Phase 6: Event Contract Normalization
Objective:
- guarantee stable tool-call event shape for consumers.

Tasks:
- update `Riffer::Voice::Events::ToolCall` to normalized hash contract.
- add/keep `arguments_hash` convenience accessor.
- ensure adapter/parser layers always emit normalized hash arguments.
- remove `String | Hash` branching from tests/docs.

Likely files:
- `lib/riffer/voice/events/tool_call.rb`
- parser/adapter normalization points
- `test/riffer/voice/events/event_objects_test.rb`

Verification gate:
- all tool-call events expose hash arguments.
- no user-facing branch needed for argument decoding.

Exit criteria:
- event contract stable and documented.

## Phase 7: Public Surface Cutover
Objective:
- remove old public voice usage path and switch docs/examples fully to session API.

Tasks:
- remove public references to `Riffer::Voice::Drivers::*` as supported API.
- remove callback-first examples from voice docs.
- rewrite `docs/10_REALTIME_VOICE.md`.
- update `docs/01_OVERVIEW.md`, `docs/02_GETTING_STARTED.md`, `docs/07_CONFIGURATION.md`.
- ensure README/doc links remain valid.

Likely files:
- `docs/10_REALTIME_VOICE.md`
- `docs/01_OVERVIEW.md`
- `docs/02_GETTING_STARTED.md`
- `docs/07_CONFIGURATION.md`
- `docs_providers/01_PROVIDERS.md`

Verification gate:
- docs reflect exactly one voice API.
- no stale references to removed public path.

Exit criteria:
- user-facing guidance matches implementation.

## Phase 8: Hardening + Release Prep
Objective:
- finalize quality bar and release artifacts.

Tasks:
- run full test suite and lint.
- add changelog entry for breaking voice redesign.
- add migration section from old to new voice API.
- review RBS generation consistency if affected.
- perform final pass on error message clarity.

Verification gate:
- full CI-equivalent local checks pass.
- changelog + migration notes complete.

Exit criteria:
- implementation ready for merge/release.

## Cross-Phase Quality Gates
Each phase must satisfy:

- tests for changed behavior added first or alongside code
- no TODO placeholders left in committed code
- follow-up file updated (status, decisions, blockers, next step)
- stop-safe commit exists at phase completion

## Suggested Commit/PR Boundaries
Recommended sequence:

1. Phase 1-2 (session + runtime core)
2. Phase 3 (event queue and event APIs)
3. Phase 4-5 (adapters + model resolver)
4. Phase 6 (event normalization)
5. Phase 7-8 (docs cutover + hardening)

If you prefer a single PR, keep these as internal commit boundaries to ease review.

## Test Plan Matrix
Required matrix before final merge:

| Area | Cases |
| --- | --- |
| Runtime modes | auto with Async present, auto without Async, async without task (error), background without Async |
| Providers | openai realtime path, gemini live path |
| Events | transcript, audio, tool call, interrupt, usage, turn complete, error |
| Tool call args | always normalized hash |
| Lifecycle | connect once, send before connect (error), close idempotency, read after close semantics |

## Risk Register
| Risk | Impact | Mitigation |
| --- | --- | --- |
| Background runtime race/deadlock | high | strict queue ownership + teardown tests |
| Adapter parity regressions | medium | provider integration tests using fixtures/fakes |
| Hidden assumptions in old tests/docs | medium | explicit surface cutover phase + grep audit |
| Breaking-change confusion | medium | migration notes + changelog callouts |

## Definition of Done
Implementation is complete when:

1. RFC acceptance criteria are satisfied.
2. Old public voice usage path is removed from user-facing docs.
3. Full tests and lint pass.
4. Follow-up file records final decisions and verification evidence.
