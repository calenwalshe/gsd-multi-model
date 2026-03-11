# Roadmap: gsd-multi-model

## Milestones

- v1.0 Core Skills (Phases 01-02) -- shipped 2026-03-03
- v1.1 Execution Pipeline (Phases 03-06) -- shipped 2026-03-05
- v1.2 Upstream Sync (Phases 07-08) -- shipped 2026-03-06
- v1.3 Safe Local-First Install -- superseded by v2.0
- v2.0 Harness Engineering (Phases 01-05) -- in progress

## Phases

<details>
<summary>v1.0-v1.2 (Phases 01-08) -- SHIPPED</summary>

See `.planning/milestones/` for archived roadmaps.

</details>

### v2.0 Harness Engineering (In Progress)

**Milestone Goal:** Close the gaps between gsd-multi-model and the harness engineering discipline — transform from a manual-step framework into an autonomous, self-driving system with deterministic quality gates and entropy management.

- [x] **Phase 01: The Orchestrator** - Build `/gsd:drive` that auto-chains discuss → plan → execute → verify → advance with internal context resets (completed 2026-03-11)
- [x] **Phase 02: Deterministic Gates** - Add pre-commit lint/test gates to execute phase and architectural constraint enforcement (completed 2026-03-11)
- [ ] **Phase 03: Entropy Management** - Wire scheduled maintenance sweeps for doc consistency, constraint violations, and stale TODOs
- [ ] **Phase 04: Observability Integration** - Config format for telemetry endpoints, executor agent telemetry queries, debug log pulling
- [ ] **Phase 05: NPM Publish & Distribution** - Publish `gsd-multi-model` to npm, version compat checks, clean GSD-base separation

## Phase Details

### Phase 01: The Orchestrator
**Goal**: Users run `/gsd:drive` and the system chains through discuss → plan → execute → verify → advance without manual `/clear` + next-command sequences
**Depends on**: v1.2 complete
**Requirements**: ORCH-01, ORCH-02, ORCH-03, ORCH-04, ORCH-05
**Plans:** 3/3 plans complete

Plans:
- [ ] 01-01-PLAN.md — Build SKILL.md entry point and drive-workflow.md state machine
- [ ] 01-02-PLAN.md — Remove --auto flag from all existing workflow files
- [ ] 01-03-PLAN.md — Wire installation pipeline and human verification

**Success Criteria** (what must be TRUE):
  1. `/gsd:drive` reads STATE.md and automatically invokes the next workflow step for the current phase
  2. Context resets happen internally between phases — user never needs to manually `/clear`
  3. The orchestrator pauses and asks the user only when there is genuine ambiguity, a verification failure, or user input is required
  4. After interruption (crash, timeout, user abort), `/gsd:drive` resumes from the correct position by reading STATE.md
  5. `/gsd:drive --phase 3` targets phase 3 specifically; `/gsd:drive --to 5` drives phases sequentially through phase 5

### Phase 02: Deterministic Gates
**Goal**: Bad code is blocked before commit by deterministic checks, not just advisory agent verification
**Depends on**: Phase 01
**Requirements**: GATE-01, GATE-02, GATE-03, GATE-04
**Plans:** 3/3 plans complete

Plans:
- [ ] 02-01-PLAN.md — Core gate scripts (gate-check.sh orchestrator, validate-architecture.sh, .architecture.json)
- [ ] 02-02-PLAN.md — Test suites for gate infrastructure (test-gate-check.sh, test-validate-architecture.sh)
- [ ] 02-03-PLAN.md — Integration wiring (gsd-tools-gate.cjs, gate-check skill, test-install.sh updates)

**Success Criteria** (what must be TRUE):
  1. During execute phase, project linters run automatically before each task commit — if linters fail, the task is blocked (not just warned)
  2. `.architecture.json` defines module dependency rules and a validator checks imports against them
  3. Agents can run structural tests against their own output before committing
  4. Gate failures produce clear, actionable messages: what rule was violated, which file, how to fix

### Phase 03: Entropy Management
**Goal**: Codebase entropy is detected and surfaced automatically between milestones, not discovered ad hoc
**Depends on**: Phase 02
**Requirements**: ENTR-01, ENTR-02, ENTR-03, ENTR-04
**Plans:** 3 plans

Plans:
- [ ] 03-01-PLAN.md — Sweep orchestrator, doc consistency checker, config schema
- [ ] 03-02-PLAN.md — Stale TODO/FIXME detector with git blame age tracking
- [ ] 03-03-PLAN.md — Test suites for sweep orchestrator and doc consistency checker

**Success Criteria** (what must be TRUE):
  1. A doc consistency check compares AGENTS.md conventions against actual code patterns and flags drift
  2. Architecture constraint violations are scanned and reported (modules importing across boundaries)
  3. Stale TODO/FIXME comments are detected with age tracking (days since introduced)
  4. Sweep schedule is configurable in `.planning/config.json` with daily/weekly/on-push options

### Phase 04: Observability Integration
**Goal**: Executor agents can query real telemetry data instead of relying solely on source code and user-pasted context
**Depends on**: Phase 02
**Requirements**: OBSV-01, OBSV-02, OBSV-03
**Success Criteria** (what must be TRUE):
  1. `.planning/config.json` supports an `observability` section with endpoint configs (log sources, error trackers)
  2. `/gsd:debug` pulls real error logs from configured endpoints when available
  3. Executor agents query telemetry before/after changes when endpoints are configured (opt-in, no-op if unconfigured)

### Phase 05: NPM Publish & Distribution
**Goal**: `npx gsd-multi-model` installs the add-on layer cleanly on top of existing GSD
**Depends on**: Phase 01 (can run in parallel with 03/04)
**Requirements**: DIST-01, DIST-02, DIST-03, DIST-04
**Success Criteria** (what must be TRUE):
  1. `npx gsd-multi-model` installs skills only (safe default); `--all` adds codex config, rules, globals
  2. Package is published to npm with correct `bin`, `files`, and metadata
  3. Install checks GSD base version against `gsd-compat.json` and warns on mismatch
  4. Installing gsd-multi-model never duplicates or overwrites base GSD files

## Progress

**Execution Order:** 01 -> 02 -> 03 (parallel with 04) -> 05

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 01. The Orchestrator | 3/3 | Complete    | 2026-03-11 | - |
| 02. Deterministic Gates | 3/3 | Complete    | 2026-03-11 | - |
| 03. Entropy Management | v2.0 | 0/3 | Planned | - |
| 04. Observability Integration | v2.0 | 0/? | Not started | - |
| 05. NPM Publish & Distribution | v2.0 | 0/? | Not started | - |
