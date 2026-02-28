# Realtime Voice Agent Refactor Plan

## Scope

This plan tracks incremental refactors for the realtime voice agent implementation with a focus on:

- Preserving current behavior and public API
- Improving Riffer DX and maintainability
- Reducing complexity and smell hotspots identified by RubyCritic

Date baseline: 2026-02-27

## Quality Baseline (RubyCritic)

Command used (lib-only PR scope):

```sh
files=(${(@f)$(git diff --name-only origin/main...HEAD -- '*.rb' | rg '^lib/.*\.rb$')})
RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rubycritic -f json --no-browser --path tmp/rubycritic-pr-json-lib "${files[@]}"
```

Results:

- Score: `63.84`
- Modules analyzed: `45`
- Ratings: `A=23, B=6, C=5, D=4, E=0, F=7`

Top hotspot files by smell count:

- `lib/riffer/voice/drivers/openai_realtime.rb` (72)
- `lib/riffer/voice/agent.rb` (64)
- `lib/riffer/voice/parsers/openai_realtime_parser.rb` (56)
- `lib/riffer/voice/drivers/gemini_live.rb` (54)

Agent-specific snapshot:

- File: `lib/riffer/voice/agent.rb`
- Rating: `F`
- Complexity: `364.03`
- Smells: `64`
- Top method complexity:
  - `initialize` (58)
  - `connect` (37)
  - `run_until_turn_complete` (33)
  - `run_loop` (31)
  - `import_state_snapshot` (28)

## Progress Checkpoint (2026-02-28)

Refactor quality gate command:

```sh
RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rake
RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rubycritic -f json --no-browser --path tmp/rubycritic-va5 \
  lib/riffer/voice/agent.rb \
  lib/riffer/voice/agent/class_configuration.rb \
  lib/riffer/voice/agent/class_configuration_helpers.rb \
  lib/riffer/voice/agent/class_connect_options.rb \
  lib/riffer/voice/agent/class_runtime_profiles.rb \
  lib/riffer/voice/agent/class_tool_defaults.rb \
  lib/riffer/voice/agent/event_loop.rb \
  lib/riffer/voice/agent/event_loop_support.rb \
  lib/riffer/voice/agent/initialization_state.rb \
  lib/riffer/voice/agent/session_lifecycle.rb \
  lib/riffer/voice/agent/state_snapshot.rb
```

Results:

- Checks: `bundle exec rake` passing (tests + standard + steep).
- RubyCritic score (touched set): `91.38`.
- Touched files are `A` or `B`:
  - `A`: `agent.rb`, `class_configuration.rb`, `class_configuration_helpers.rb`, `class_connect_options.rb`, `class_runtime_profiles.rb`, `class_tool_defaults.rb`, `event_loop.rb`, `initialization_state.rb`, `state_snapshot.rb`
  - `B`: `event_loop_support.rb`, `session_lifecycle.rb`

## Progress Checkpoint (2026-02-28, VA5)

Refactor quality gate command:

```sh
RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rake
bundle exec rubycritic -f json --no-browser --path tmp/rubycritic-va5-final2 \
  lib/riffer/voice/drivers/base.rb \
  lib/riffer/voice/drivers/runtime_support.rb \
  lib/riffer/voice/drivers/realtime_lifecycle_support.rb \
  lib/riffer/voice/drivers/openai_realtime.rb \
  lib/riffer/voice/drivers/openai_realtime_connection.rb \
  lib/riffer/voice/drivers/openai_realtime_session_config.rb \
  lib/riffer/voice/drivers/openai_realtime_response_state.rb \
  lib/riffer/voice/drivers/openai_realtime_response_flow.rb \
  lib/riffer/voice/drivers/openai_realtime_response_logging.rb \
  lib/riffer/voice/drivers/openai_realtime_audio.rb \
  lib/riffer/voice/drivers/openai_realtime_lifecycle.rb \
  lib/riffer/voice/drivers/openai_realtime_dispatch.rb \
  lib/riffer/voice/drivers/gemini_live.rb \
  lib/riffer/voice/drivers/gemini_live_connection.rb \
  lib/riffer/voice/drivers/gemini_live_payloads.rb \
  lib/riffer/voice/drivers/gemini_live_lifecycle.rb \
  lib/riffer/voice/drivers/gemini_live_dispatch.rb
```

Results:

- Checks: `bundle exec rake` passing (tests + standard + steep).
- RubyCritic score (touched set): `87.73`.
- Touched driver files are `A` or `B`:
  - `A`: `gemini_live.rb`, `gemini_live_dispatch.rb`, `openai_realtime.rb`, `openai_realtime_dispatch.rb`, `openai_realtime_response_logging.rb`, `openai_realtime_response_state.rb`, `realtime_lifecycle_support.rb`, `runtime_support.rb`
  - `B`: `base.rb`, `gemini_live_connection.rb`, `gemini_live_lifecycle.rb`, `gemini_live_payloads.rb`, `openai_realtime_audio.rb`, `openai_realtime_connection.rb`, `openai_realtime_lifecycle.rb`, `openai_realtime_response_flow.rb`, `openai_realtime_session_config.rb`

## Progress Checkpoint (2026-02-28, VA6)

Refactor quality gate command:

```sh
RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rake
bundle exec rubycritic -f json --no-browser --path tmp/rubycritic-va6 \
  lib/riffer/voice/parsers/openai_realtime_parser.rb \
  lib/riffer/voice/parsers/openai_realtime_parser_constants.rb \
  lib/riffer/voice/parsers/openai_realtime_parser_dispatch.rb \
  lib/riffer/voice/parsers/openai_realtime_parser_content.rb \
  lib/riffer/voice/parsers/openai_realtime_parser_response.rb \
  lib/riffer/voice/parsers/openai_realtime_parser_tools.rb
```

Results:

- Checks: `bundle exec rake` passing (tests + standard + steep).
- RubyCritic score (touched set): `90.52`.
- Touched parser files are `A` or `B`:
  - `A`: `openai_realtime_parser.rb`, `openai_realtime_parser_constants.rb`, `openai_realtime_parser_dispatch.rb`, `openai_realtime_parser_tools.rb`
  - `B`: `openai_realtime_parser_content.rb`, `openai_realtime_parser_response.rb`

## Implementation Sequence

Use this order for the best impact/effort ratio:

1. Agent normalization and validation extraction
2. Nil-check/repeated-conditional cleanup
3. Run-loop context consolidation
4. Agent orchestration decomposition
5. Driver deduplication
6. OpenAI parser split
7. CI quality guardrails

## Work Items

Status legend: `[ ] todo`, `[~] in progress`, `[x] done`

### VA1. Agent normalization and validation extraction

- [x] Extract connect options normalization from `Agent#connect` to a focused object/module.
- [x] Extract initialization/config validation from `Agent#initialize` to a focused object/module.
- [x] Keep `Riffer::Voice::Agent.connect` and constructor API unchanged.
- [x] Preserve all existing tests and add/adjust unit tests for extracted components.

Success criteria:

- `Agent#connect` and `Agent#initialize` become orchestration-level methods.
- RubyCritic method complexity for both methods decreases from baseline.

### VA2. Nil-check and repeated-conditional cleanup

- [x] Introduce intent-revealing helpers (example: tool handling enabled, timeout deadline, default profile config).
- [x] Replace repeated `nil` branching in run/connect flows with helper methods.
- [x] Remove duplicate method call hotspots where behavior stays identical.

Success criteria:

- Reduced `NilCheck`, `DuplicateMethodCall`, and `RepeatedConditional` counts for `agent.rb`.

### VA3. Run-loop context consolidation

- [x] Add a lightweight run-loop support layer for shared run-loop argument handling.
- [x] Refactor `run_loop`, `run_until_turn_complete`, and event consumption methods to use extracted orchestration helpers.
- [x] Preserve external behavior and timing semantics.

Success criteria:

- `DataClump` and long argument flow reduced in `agent.rb`.
- No regressions in session/event loop tests.

### VA4. Agent orchestration decomposition

- [x] Move remaining heavy orchestration blocks from `agent.rb` into dedicated collaborators.
- [x] Keep `Agent` as thin façade/coordinator.
- [x] Ensure extracted classes follow existing Riffer naming and loading conventions.

Success criteria:

- `agent.rb` drops major smell load and total method/statement pressure.
- No public API changes.

### VA5. Driver deduplication

- [x] Identify shared translation logic between OpenAI and Gemini drivers.
- [x] Move shared behavior to `drivers/base` or a dedicated internal helper.
- [x] Preserve provider-specific behavior in leaf drivers.

Success criteria:

- Lower `DuplicateCode` and `TooManyStatements` in driver files.
- Existing driver tests pass without semantic changes.

### VA6. OpenAI parser split

- [x] Split OpenAI realtime parser into event-specific handlers or dispatch table structure.
- [x] Keep parser public contract unchanged.
- [x] Add tests at handler boundaries where useful.

Success criteria:

- Lower parser complexity and clearer event mapping flow.
- Existing parser tests remain green.

### VA7. CI quality guardrails

- [ ] Add or update a reproducible RubyCritic task focused on `lib/riffer/voice/**`.
- [ ] Keep guardrail non-blocking first, then evolve toward threshold checks.
- [ ] Document how to run and interpret quality checks in repo docs.

Success criteria:

- Quality trend is visible in CI and can be tracked per PR.

## Tracking Table

| Item | Status | PR | Notes |
|---|---|---|---|
| VA1 | `[x]` | current branch | `ClassConnectOptions` + `InitializationState` extracted. |
| VA2 | `[x]` | current branch | Nil-check and duplicate dispatch reduced via focused class DSL/runtime modules and helpers. |
| VA3 | `[x]` | current branch | Event loop orchestration moved to `event_loop` + `event_loop_support`. |
| VA4 | `[x]` | current branch | Session lifecycle and snapshot orchestration extracted; `agent.rb` now thin coordinator (`A`). |
| VA5 | `[x]` | current branch | Shared runtime/lifecycle helpers + split OpenAI/Gemini driver concerns into focused modules. |
| VA6 | `[x]` | current branch | OpenAI realtime parser split into dispatch/constants/content/response/tools modules, preserving parser API and tests. |
| VA7 | `[ ]` |  |  |

## Definition Of Done

- Behavior parity preserved for realtime voice agent and tool execution flows.
- `bundle exec rake` passes.
- RubyCritic report regenerated and attached/linked in PR notes.
- Plan tracker updated (status, PR links, notes).
