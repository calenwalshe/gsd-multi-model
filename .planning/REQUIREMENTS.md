# Requirements: gsd-multi-model

**Defined:** 2026-03-11
**Core Value:** Structured dual-tool workflow that drives itself through the full loop with deterministic quality gates

## v2.0 Requirements

Requirements for Harness Engineering milestone. Each maps to roadmap phases.

### Orchestration

- [x] **ORCH-01**: `/gsd:drive` auto-chains discuss → plan → execute → verify → advance for a given phase
- [x] **ORCH-02**: Orchestrator handles context resets between phases internally (no manual `/clear`)
- [x] **ORCH-03**: Orchestrator pauses only on genuine decision points (ambiguous requirements, verification failures, user input needed)
- [x] **ORCH-04**: Orchestrator reads STATE.md to resume from any position after interruption
- [x] **ORCH-05**: Orchestrator supports `--phase N` to target a specific phase and `--to N` to drive through a range

### Deterministic Gates

- [x] **GATE-01**: Execute phase runs project linters before allowing task commit (fail = task blocked)
- [x] **GATE-02**: `.architecture.json` format defines allowed dependency directions between modules
- [x] **GATE-03**: Structural test scaffolding that agents run against their own output before commit
- [x] **GATE-04**: Gate failures produce actionable error messages (what failed, what to fix)

### Entropy Management

- [ ] **ENTR-01**: Scheduled doc consistency check (do AGENTS.md conventions match actual code patterns?)
- [ ] **ENTR-02**: Constraint violation scanning between milestones (architecture rules still hold?)
- [x] **ENTR-03**: Stale TODO/FIXME detection with age tracking
- [ ] **ENTR-04**: Configurable schedule via `.planning/config.json` (daily/weekly/on-push)

### Observability

- [ ] **OBSV-01**: `.planning/config.json` supports observability endpoint config (log sources, error trackers)
- [ ] **OBSV-02**: `/gsd:debug` can pull real error logs from configured endpoints
- [ ] **OBSV-03**: Executor agents query telemetry before/after changes when endpoints are configured

### Distribution

- [ ] **DIST-01**: `npx gsd-multi-model` installs skills (default), with `--all` for full setup
- [ ] **DIST-02**: Package published to npm with correct `bin` entry and `files` manifest
- [ ] **DIST-03**: Version compatibility check against base GSD on install
- [ ] **DIST-04**: Clean separation — GSD base is prerequisite, multi-model is add-on only

## Future Requirements

### Progressive Context

- **PCTX-01**: Executors receive only their task slice + relevant rules, not all planning state
- **PCTX-02**: Context budget tracking to prevent instruction crowding

### Team Scale

- **TEAM-01**: Harness versioning for tracking config changes over time
- **TEAM-02**: A/B testing different harness configurations

## Out of Scope

| Feature | Reason |
|---------|--------|
| External daemon for orchestration | Must work within Claude Code's session model |
| Harness A/B testing | Team-scale concern, not solo developer |
| Custom model routing beyond profiles | Fixed quality/balanced/budget tiers sufficient |
| Gemini/OpenCode integration | Claude + Codex only |
| Runtime version checking | Install-time only, no overhead |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ORCH-01 | Phase 01 | Complete |
| ORCH-02 | Phase 01 | Complete |
| ORCH-03 | Phase 01 | Complete |
| ORCH-04 | Phase 01 | Complete |
| ORCH-05 | Phase 01 | Complete |
| GATE-01 | Phase 02 | Complete |
| GATE-02 | Phase 02 | Complete |
| GATE-03 | Phase 02 | Complete |
| GATE-04 | Phase 02 | Complete |
| ENTR-01 | Phase 03 | Pending |
| ENTR-02 | Phase 03 | Pending |
| ENTR-03 | Phase 03 | Complete |
| ENTR-04 | Phase 03 | Pending |
| OBSV-01 | Phase 04 | Pending |
| OBSV-02 | Phase 04 | Pending |
| OBSV-03 | Phase 04 | Pending |
| DIST-01 | Phase 05 | Pending |
| DIST-02 | Phase 05 | Pending |
| DIST-03 | Phase 05 | Pending |
| DIST-04 | Phase 05 | Pending |

**Coverage:**
- v2.0 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0

---
*Requirements defined: 2026-03-11*
*Last updated: 2026-03-11 after v2.0 milestone creation*
