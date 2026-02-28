# Voice Agent Follow-up Tracker

Date created: 2026-02-28  
Scope: Full implementation of `Riffer::Voice::Agent` in `riffer`

## Tracking Rules

- Keep entries chronological (newest first).
- Record objective evidence:
  - changed files
  - commands run
  - test/lint results
- Update this file at the end of each meaningful implementation session.

## Status Legend

- `PLANNED` = defined but not started
- `IN_PROGRESS` = implementation underway
- `BLOCKED` = waiting on unresolved decision/dependency
- `DONE` = implemented and verified

## Milestones

| ID | Milestone | Status | Owner | Notes |
| --- | --- | --- | --- | --- |
| VA1 | API + DSL hardening | DONE | Riffer maintainers | added runtime/config/auto-tool defaults + precedence/validation coverage |
| VA2 | Callback registry + event router | DONE | Riffer maintainers | `on_event` + typed callbacks with deterministic failure policy |
| VA3 | Tool execution pipeline + hooks | DONE | Riffer maintainers | pluggable executor + lifecycle hooks + schema-hash behavior |
| VA4 | Role profiles | DONE | Riffer maintainers | profile DSL + `connect(profile: ...)` with deterministic precedence |
| VA5 | Policy gates + action budgets | PLANNED | Riffer maintainers | generic guard hooks for mutation/action control |
| VA6 | Run helpers + lifecycle semantics | PLANNED | Riffer maintainers | `run_loop`, turn-complete helper, drain helpers |
| VA7 | Durability hooks | PLANNED | Riffer maintainers | checkpoint/snapshot hooks, app-managed persistence |
| VA8 | Docs/examples/migration guidance | PLANNED | Riffer maintainers | Session vs Voice Agent, profile/policy/durability examples |
| VA9 | Test matrix + final QA | PLANNED | Riffer maintainers | runtime/tool/profile/policy/durability matrix and suite verification |

## Task Checklist

- [x] Add class-level default runtime/voice config/auto-tool settings.
- [x] Add callback registration API for all voice event types.
- [x] Add callback failure handling contract and tests.
- [x] Add custom tool executor injection contract.
- [x] Add before/after/on-error tool execution hooks.
- [x] Add profile DSL and profile-aware connect path.
- [ ] Add policy hooks (approval + budget + mutation classifier interface).
- [ ] Add helper methods for common event loops.
- [ ] Add snapshot/checkpoint hooks for durability integration.
- [ ] Add migration examples from manual session loops.
- [ ] Expand tests for async/background runtime matrix.
- [ ] Run full quality gates and record results.

## Decisions Log

| Date | Decision | Rationale | Impact |
| --- | --- | --- | --- |
| 2026-02-28 | Keep `Voice::Agent` separate from `Voice::Session` | preserves low-level primitive + additive DX | avoids coupling orchestration to transport internals |
| 2026-02-28 | Use existing `Riffer::Tool#call_with_validation` as default execution path | behavior parity with text `Riffer::Agent` | consistent validation/timeout/error semantics |
| 2026-02-28 | Adopt selected Notion architecture patterns only (roles, policy, durability hooks) | high-leverage DX improvements with low coupling | faster path to robust framework API |
| 2026-02-28 | Defer Cortex/memory-authoring architecture from Riffer core | belongs to app/platform layers, not framework runtime | keeps Riffer focused and portable |

## Risks and Blockers

| Date | Type | Description | Owner | Status | Mitigation |
| --- | --- | --- | --- | --- | --- |
| 2026-02-28 | Risk | API growth may reduce Voice Agent simplicity | Riffer maintainers | Open | keep strict default path, move advanced behavior behind opt-in hooks |
| 2026-02-28 | Risk | Callback/policy errors may be ambiguous for users | Riffer maintainers | Open | define explicit policy and cover in tests/docs |
| 2026-02-28 | Risk | Runtime-mode behavior drift (`:async` vs `:background`) | Riffer maintainers | Open | enforce runtime matrix tests in VA9 |
| 2026-02-28 | Risk | Durability expectations could imply built-in persistence | Riffer maintainers | Open | expose hooks only; explicitly document storage as app responsibility |

## QA Run Log

| Date | Command | Result | Notes |
| --- | --- | --- | --- |
| 2026-02-28 | `bundle exec ruby -Ilib:test test/riffer/voice/agent_test.rb` | Pass | VA4 profile coverage added (`30 runs, 0 failures`) |
| 2026-02-28 | `bundle exec ruby -Ilib:test test/riffer/voice/session_test.rb` | Pass | regression check after VA4 profile changes |
| 2026-02-28 | `bundle exec ruby -Ilib:test test/riffer/voice/connect_validation_test.rb` | Pass | connect/validation behavior preserved after VA4 |
| 2026-02-28 | `RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rake standard` | Pass | VA4 lint pass |
| 2026-02-28 | `bundle exec ruby -Ilib:test test/riffer/voice/agent_test.rb` | Pass | VA3 executor/hooks coverage added (`25 runs, 0 failures`) |
| 2026-02-28 | `bundle exec ruby -Ilib:test test/riffer/voice/session_test.rb` | Pass | regression check after VA3 pipeline changes |
| 2026-02-28 | `bundle exec ruby -Ilib:test test/riffer/voice/connect_validation_test.rb` | Pass | connect/validation behavior preserved after VA3 |
| 2026-02-28 | `RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rake standard` | Pass | VA3 lint pass |
| 2026-02-28 | `bundle exec ruby -Ilib:test test/riffer/voice/agent_test.rb` | Pass | VA2 callback coverage added (`20 runs, 0 failures`) |
| 2026-02-28 | `bundle exec ruby -Ilib:test test/riffer/voice/session_test.rb` | Pass | regression check after VA2 callback router |
| 2026-02-28 | `bundle exec ruby -Ilib:test test/riffer/voice/connect_validation_test.rb` | Pass | connect/validation behavior preserved |
| 2026-02-28 | `RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rake standard` | Pass | VA2 lint pass |
| 2026-02-28 | `bundle exec ruby -Ilib:test test/riffer/voice/agent_test.rb` | Pass | VA1 expanded coverage (`15 runs, 0 failures`) |
| 2026-02-28 | `RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rake standard` | Pass | VA1 lint pass |
| 2026-02-28 | `bundle exec ruby -Ilib:test test/riffer/voice/agent_test.rb` | Pass | baseline Voice Agent tests |
| 2026-02-28 | `bundle exec ruby -Ilib:test test/riffer/voice/session_test.rb` | Pass | no regression in session semantics |
| 2026-02-28 | `bundle exec ruby -Ilib:test test/riffer/voice/connect_validation_test.rb` | Pass | connect/tool validation preserved |
| 2026-02-28 | `RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rake standard` | Pass | style checks passed |

## Session Change Log (Newest First)

## 2026-02-28

- Completed VA4 (`Role profiles`) with:
  - class-level profile DSL: `profile :name do ... end`.
  - profile-aware connect path via `connect(profile: ...)`.
  - profile precedence integrated for:
    - `model`
    - `instructions`
    - `tools`
    - `runtime`
    - `voice_config`
    - `tool_executor`
  - deterministic profile validation errors (invalid name, unknown profile, invalid profile fields).
  - expanded tests in `test/riffer/voice/agent_test.rb` for profile resolution and override precedence.
- Updated docs:
  - `docs/10_REALTIME_VOICE.md` (Voice Agent Profiles section)
- Next step:
  - execute VA5 from `docs/voice-agent-implementation-plan.md`.

- Completed VA3 (`Tool execution pipeline + hooks`) with:
  - pluggable `tool_executor` (class-level and instance-level injection).
  - lifecycle hooks:
    - `on_before_tool_execution`
    - `on_after_tool_execution`
    - `on_tool_execution_error`
  - explicit schema-hash tool behavior:
    - returns `external_tool_executor_required` when tool is schema-only and no executor is provided.
  - expanded tests in `test/riffer/voice/agent_test.rb` for executor strategy, hook invocation, and schema-hash error behavior.
- Updated docs:
  - `docs/10_REALTIME_VOICE.md` (tool executor + hooks section)
- Next step:
  - execute VA4 from `docs/voice-agent-implementation-plan.md`.

- Completed VA2 (`Callback registry + event router`) with:
  - callback registration API in `Riffer::Voice::Agent`:
    - `on_event`
    - `on_audio_chunk`
    - `on_input_transcript`
    - `on_output_transcript`
    - `on_tool_call`
    - `on_interrupt`
    - `on_turn_complete`
    - `on_usage`
    - `on_error`
  - callback dispatch integrated in both `next_event` and `events`.
  - deterministic callback failure contract:
    - callback exceptions raise `Riffer::Error` with callback key + event class context.
  - expanded tests in `test/riffer/voice/agent_test.rb` for callback registration, dispatch, and failure behavior.
- Updated docs:
  - `docs/10_REALTIME_VOICE.md` (Voice Agent callbacks section)
- Next step:
  - execute VA3 from `docs/voice-agent-implementation-plan.md`.

- Completed VA1 (`API + DSL hardening`) with:
  - class DSL defaults in `Riffer::Voice::Agent`:
    - `runtime`
    - `voice_config`
    - `auto_handle_tool_calls`
  - explicit resolution/validation for resolved model, tools, config, runtime.
  - documented precedence and deep-merge behavior for `voice_config` + `connect(config:)`.
  - expanded tests in `test/riffer/voice/agent_test.rb` for defaults, overrides, and validation errors.
- Updated docs:
  - `docs/10_REALTIME_VOICE.md` (Voice Agent defaults + precedence section)
- Next step:
  - execute VA2 from `docs/voice-agent-implementation-plan.md`.

- Reviewed Notion architecture page through MCP (`Jane.ai — Agent Jane Architecture`) and extracted framework-fit opportunities.
- Refactored planning docs to include Notion-inspired but scoped additions:
  - role profiles
  - policy gates + action budgets
  - durability hooks
- Explicitly documented deferrals for Cortex/memory-authoring architecture to keep `riffer` scope clean.
- Next step:
  - execute VA1 and VA2 from `docs/voice-agent-implementation-plan.md`.
