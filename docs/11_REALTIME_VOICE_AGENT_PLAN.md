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

- [ ] Extract connect options normalization from `Agent#connect` to a focused object/module.
- [ ] Extract initialization/config validation from `Agent#initialize` to a focused object/module.
- [ ] Keep `Riffer::Voice::Agent.connect` and constructor API unchanged.
- [ ] Preserve all existing tests and add/adjust unit tests for extracted components.

Success criteria:

- `Agent#connect` and `Agent#initialize` become orchestration-level methods.
- RubyCritic method complexity for both methods decreases from baseline.

### VA2. Nil-check and repeated-conditional cleanup

- [ ] Introduce intent-revealing helpers (example: tool handling enabled, timeout deadline, default profile config).
- [ ] Replace repeated `nil` branching in run/connect flows with helper methods.
- [ ] Remove duplicate method call hotspots where behavior stays identical.

Success criteria:

- Reduced `NilCheck`, `DuplicateMethodCall`, and `RepeatedConditional` counts for `agent.rb`.

### VA3. Run-loop context consolidation

- [ ] Add a lightweight run context value object for shared run-loop arguments.
- [ ] Refactor `run_loop`, `run_until_turn_complete`, and event consumption methods to use the context.
- [ ] Preserve external behavior and timing semantics.

Success criteria:

- `DataClump` and long argument flow reduced in `agent.rb`.
- No regressions in session/event loop tests.

### VA4. Agent orchestration decomposition

- [ ] Move remaining heavy orchestration blocks from `agent.rb` into dedicated collaborators.
- [ ] Keep `Agent` as thin façade/coordinator.
- [ ] Ensure extracted classes follow existing Riffer naming and loading conventions.

Success criteria:

- `agent.rb` drops major smell load and total method/statement pressure.
- No public API changes.

### VA5. Driver deduplication

- [ ] Identify shared translation logic between OpenAI and Gemini drivers.
- [ ] Move shared behavior to `drivers/base` or a dedicated internal helper.
- [ ] Preserve provider-specific behavior in leaf drivers.

Success criteria:

- Lower `DuplicateCode` and `TooManyStatements` in driver files.
- Existing driver tests pass without semantic changes.

### VA6. OpenAI parser split

- [ ] Split OpenAI realtime parser into event-specific handlers or dispatch table structure.
- [ ] Keep parser public contract unchanged.
- [ ] Add tests at handler boundaries where useful.

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
| VA1 | `[ ]` |  |  |
| VA2 | `[ ]` |  |  |
| VA3 | `[ ]` |  |  |
| VA4 | `[ ]` |  |  |
| VA5 | `[ ]` |  |  |
| VA6 | `[ ]` |  |  |
| VA7 | `[ ]` |  |  |

## Definition Of Done

- Behavior parity preserved for realtime voice agent and tool execution flows.
- `bundle exec rake` passes.
- RubyCritic report regenerated and attached/linked in PR notes.
- Plan tracker updated (status, PR links, notes).
