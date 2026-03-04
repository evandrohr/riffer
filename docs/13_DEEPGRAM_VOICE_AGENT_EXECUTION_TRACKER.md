# Deepgram Voice Agent Execution Tracker

Date created: 2026-03-04
Owner: TBD
Status: Active
Related plan: `docs/12_DEEPGRAM_VOICE_AGENT_PLAN.md`

## 1. Tracking Rules

1. Keep one active item marked `IN_PROGRESS` per phase.
2. Update `Last updated` and `Updated by` on every status change.
3. Log blockers in Section 6 immediately.
4. Do not mark a phase complete unless its exit criteria are met.

## 2. Status Legend

- `TODO`
- `IN_PROGRESS`
- `BLOCKED`
- `DONE`

## 3. Master Checklist

| ID | Work Package | Status | Owner | Start | End | Notes |
|---|---|---|---|---|---|---|
| WP1 | Configuration and model resolution | DONE | Codex | 2026-03-04 | 2026-03-04 | Added `deepgram` config + model resolver + tests |
| WP2 | Adapter and driver registration | DONE | Codex | 2026-03-04 | 2026-03-04 | Added adapter/driver classes and repository wiring |
| WP3 | Binary-capable transport contract | DONE | Codex | 2026-03-04 | 2026-03-04 | Added `write_binary` API + transport tests |
| WP4 | Deepgram parser implementation | DONE | Codex | 2026-03-04 | 2026-03-04 | Added parser and tests for text/tool/error/turn/interrupt |
| WP5 | Driver lifecycle and handshake | DONE | Codex | 2026-03-04 | 2026-03-04 | Added connect/read-loop/cleanup + Settings handshake |
| WP6 | Outbound dispatch mapping | DONE | Codex | 2026-03-04 | 2026-03-04 | Added audio/text/tool response dispatch mappings |
| WP7 | Tool-calling interoperability policy | IN_PROGRESS | Codex | 2026-03-04 | - | Client-side execution gating implemented; server-response metadata handling pending |
| WP8 | Documentation and examples | TODO | TBD | - | - | docs + usage sample |

## 4. Phase Exit Criteria

### Phase A (WP1-WP4)

- [ ] `deepgram/...` resolves and validates config correctly.
- [ ] Binary transport tests pass.
- [ ] Parser tests cover `FunctionCallRequest` and malformed args.

Phase A status: DONE

### Phase B (WP5-WP6)

- [ ] Driver connects with auth header and writes `Settings` first.
- [ ] Read loop handles JSON and binary frames.
- [ ] `send_audio_chunk`, `send_text_turn`, and `send_tool_response` map correctly.

Phase B status: DONE

### Phase C (WP7)

- [ ] `client_side: true` function calls emit `ToolCall` and auto-execute.
- [ ] `client_side: false` does not trigger local tool execution.
- [ ] No duplicate tool execution when server function responses are present.

Phase C status: IN_PROGRESS

### Phase D (WP8)

- [ ] Deepgram docs added and cross-linked.
- [ ] End-to-end example validated.
- [ ] Full `bundle exec rake` passing.

Phase D status: TODO

## 5. Test Matrix

| Test Area | File(s) | Status | Notes |
|---|---|---|---|
| Model resolver | `test/riffer/voice/model_resolver_test.rb` | TODO | add deepgram cases |
| Connect validation | `test/riffer/voice/connect_validation_test.rb` | TODO | add deepgram key checks |
| Adapter registry | `test/riffer/voice/adapters/repository_test.rb` | TODO | include deepgram adapter |
| Driver registry | `test/riffer/voice/drivers/repository_test.rb` | TODO | include deepgram driver |
| Parser | `test/riffer/voice/parsers/deepgram_voice_agent_parser_test.rb` | TODO | new file |
| Driver | `test/riffer/voice/drivers/deepgram_voice_agent_test.rb` | TODO | new file |
| Adapter | `test/riffer/voice/adapters/deepgram_voice_agent_test.rb` | TODO | new file |
| Transport binary | `test/riffer/voice/transports/*` | TODO | extend existing transport tests |
| End-to-end behavior | driver + session tests | TODO | tool-call round-trip |

## 6. Blockers Log

| Date | Blocker | Impact | Owner | Resolution |
|---|---|---|---|---|
| - | - | - | - | - |

## 7. Decisions Log

| Date | Decision | Why | Consequence |
|---|---|---|---|
| 2026-03-04 | Ship native Deepgram Voice Agent provider first | Lowest integration risk with existing `Riffer::Voice::Session` contract | Flux transport mode deferred |
| 2026-03-04 | Gate local tool execution on `client_side: true` only | Prevent server-side function double execution | Clear interoperability policy |
| 2026-03-04 | Deepgram default `think.provider.type` set to `open_ai` | Align `deepgram/<model>` with practical defaults while keeping `config` overrides | Users can switch provider type via `config` without API break |

## 8. Implementation Journal

### Entry template

- Date:
- Author:
- Scope:
- Changes:
- Tests run:
- Result:
- Follow-ups:

### Entries

- Date: 2026-03-04
- Author: Codex
- Scope: Planning + tracking setup
- Changes:
  - Created detailed plan at `docs/12_DEEPGRAM_VOICE_AGENT_PLAN.md`
  - Created this tracker file
  - Added extra Deepgram tool-calling research references and mapping policy
- Tests run:
  - none (documentation-only changes)
- Result:
  - planning artifacts ready for implementation kickoff
- Follow-ups:
  - start WP1 with config/model resolver updates and corresponding tests

- Date: 2026-03-04
- Author: Codex
- Scope: WP1-WP6 implementation + WP7 kickoff
- Changes:
  - Added `deepgram` configuration and model resolution path
  - Added `DeepgramVoiceAgent` adapter and driver with lifecycle/dispatch modules
  - Added binary websocket write support for async/thread transports
  - Added `DeepgramVoiceAgentParser` for text/tool/error/interrupt/turn events
  - Added and updated test coverage for resolver/validation/repositories/transports/parser/adapter/driver
- Tests run:
  - `bundle exec rake test`
  - `RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rake standard`
  - `bundle exec rake steep:check`
  - `RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rake`
- Result:
  - all checks passing
- Follow-ups:
  - finish WP7 server-side function response metadata strategy
  - execute WP8 docs+examples updates

## 9. Weekly Snapshot

### Week of 2026-03-02

- Overall completion: 0%
- Active phase: Phase C in progress
- This week target:
  - [x] Complete WP1 and WP2
  - [x] Complete WP3
  - [x] Complete WP4
  - [x] Complete WP5
  - [x] Complete WP6
  - [ ] Complete WP7
  - [ ] Start WP8

## 10. Last Updated

- Last updated: 2026-03-04
- Updated by: Codex
