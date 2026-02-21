# Realtime Voice Execution Follow-Up

Status: In progress  
Last updated: 2026-02-21  
Owner: Voice platform team

## Milestone tracker

| Milestone | Scope | Status | Evidence | Notes |
|---|---|---|---|---|
| Phase 1 | Contracts + events + repository | Done | Voice event/repository tests | |
| Phase 2 | Async transport + parsers | Done | Parser tests | |
| Phase 3 | Gemini driver | Done | Gemini driver tests | |
| Phase 4 | OpenAI driver | Done | OpenAI driver tests | |
| Phase 5 | Consumer adoption (`voice_inteligence`, `jane`) | Not started | | |
| Phase 6 | Docs + release notes | In progress | This document + plan doc | |

## Phase checklists

### Phase 1 checklist

- [x] `Riffer::Voice` namespaces added
- [x] `Drivers::Base` added
- [x] `Events::*` classes added
- [x] `Drivers::Repository` added
- [x] Unit tests for events and repository added
- [x] Type signatures generated/validated in CI checks

### Phase 2 checklist

- [x] Async websocket transport adapter added
- [x] Gemini payload parser added
- [x] OpenAI realtime parser added
- [x] Parser tests for canonical payloads added
- [x] Parser tests for malformed/edge payload handling added

### Phase 3 checklist

- [x] Gemini connect/setup implemented
- [x] Gemini send audio/text/tool response implemented
- [x] Gemini reader loop emits normalized events
- [x] Gemini close is idempotent
- [x] Gemini driver tests added

### Phase 4 checklist

- [x] OpenAI connect/session.update implemented
- [x] OpenAI send audio/text/tool response implemented
- [x] OpenAI reader loop emits normalized events
- [x] OpenAI close is idempotent
- [x] OpenAI driver tests added

### Phase 5 checklist

- [ ] `voice_inteligence` adapter created
- [ ] Gemini flow routed through riffer driver in shadow mode
- [ ] OpenAI path adapter created
- [ ] `jane` adapter created
- [ ] Compatibility/parity checklist signed off

### Phase 6 checklist

- [x] Plan document created (`docs/10_REALTIME_VOICE_PLAN.md`)
- [x] Follow-up document created (`docs/11_REALTIME_VOICE_EXECUTION_FOLLOW_UP.md`)
- [ ] `README` voice section updated
- [ ] provider docs overview updated
- [ ] configuration docs updated for Gemini voice key usage
- [ ] changelog entry added

## PR / implementation log

| Date | Change | Status | Notes |
|---|---|---|---|
| 2026-02-21 | Added `Riffer::Voice` subsystem (events, parsers, drivers, transport) | Done | Driver-only scope |
| 2026-02-21 | Added Gemini + OpenAI realtime driver tests | Done | Includes callback and close behavior |
| 2026-02-21 | Added Gemini config namespace support | Done | `Riffer.config.gemini.api_key` |

## Test evidence

| Date | Command | Result |
|---|---|---|
| 2026-02-21 | `bundle exec ruby -Ilib:test test/riffer/voice/...` | Pass |
| 2026-02-21 | `RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rake standard` | Pass |
| 2026-02-21 | `RUBOCOP_CACHE_ROOT=tmp/rubocop_cache bundle exec rake` | Pass |

## Risk/issues log

| Risk/Issue | Impact | Mitigation | Status |
|---|---|---|---|
| Provider event schema drift | Medium | Keep provider-specific mapping isolated in parser classes | Open |
| Consumer app migration complexity | Medium | Phase 5 adapter-based rollout with parity checks | Open |
| Runtime misuse outside Async context | Medium | Driver fails fast with explicit error | Mitigated |

## Decision log

| Date | Decision | Reason |
|---|---|---|
| 2026-02-21 | v1 is driver-only (no session helper) | Keep riffer API minimal and host-owned orchestration |
| 2026-02-21 | Fiber runtime is Async stack | Consistency with existing voice implementations and Ruby scheduler model |
| 2026-02-21 | Host executes tools | Avoid coupling business logic into driver layer |

## Consumer adoption tracking

### `voice_inteligence`

- [ ] Adapter around `Riffer::Voice::Drivers::Repository.find(:gemini_live)`
- [ ] Replace direct Gemini protocol client behind flag
- [ ] Add OpenAI adapter path

### `jane`

- [ ] Mirror adapter seam in communication voice intelligence namespace
- [ ] Verify Gemini parity
- [ ] Enable OpenAI path after parity sign-off
