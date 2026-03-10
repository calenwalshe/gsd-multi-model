# Roadmap: gsd-multi-model

## Milestones

- v1.0 Core Skills (Phases 01-02) -- shipped 2026-03-03
- v1.1 Execution Pipeline (Phases 03-06) -- shipped 2026-03-05
- v1.2 Upstream Sync (Phases 07-08) -- shipped 2026-03-06
- v1.3 Safe Local-First Install (Phases 09-10) -- in progress

## Phases

<details>
<summary>v1.0-v1.2 (Phases 01-08) -- SHIPPED</summary>

See `.planning/milestones/` for archived roadmaps.

</details>

### v1.3 Safe Local-First Install (In Progress)

**Milestone Goal:** Make the dual-tool workflow testable in a single project without modifying the global GSD setup -- zero risk to existing workflow.

- [ ] **Phase 09: Local-First Install** - Modify /init-gsd to scaffold project-local config files with absolute repo paths, skipping global modifications when base GSD is detected
- [ ] **Phase 10: Coexistence Validation** - Verify addon skills coexist with base GSD without collisions and build test suites that prove local-only install and base GSD integrity

## Phase Details

### Phase 09: Local-First Install
**Goal**: Users can run /init-gsd in any project and get a working dual-tool setup without any global side effects
**Depends on**: Phase 08 (v1.2 complete)
**Requirements**: INST-01, INST-02, INST-03, INST-04, COEX-02
**Success Criteria** (what must be TRUE):
  1. Running /init-gsd in a project creates a CLAUDE.md in the project root (not ~/.claude/CLAUDE.md) containing dual-tool workflow instructions
  2. Running /init-gsd in a project creates .claude/rules/ in the project directory (not ~/.claude/rules/) with dual-tool rules
  3. All bin/ script references in the generated config use absolute paths to the cloned gsd-multi-model repo (not relative paths or symlinks to global install)
  4. When base GSD is already installed globally, /init-gsd detects it and skips all global modifications (no writes to ~/.claude/ directory tree)
**Plans**: TBD

Plans:
- [ ] 09-01: TBD
- [ ] 09-02: TBD

### Phase 10: Coexistence Validation
**Goal**: Addon skills and base GSD operate side-by-side without interference, proven by automated tests
**Depends on**: Phase 09
**Requirements**: COEX-01, COEX-03, VALID-01, VALID-02
**Success Criteria** (what must be TRUE):
  1. Addon skills (init-gsd, codex-review, gsd-codex-verify) are installed in the global skills directory without overwriting or shadowing any base GSD /gsd:* commands
  2. Base GSD commands (/gsd:progress, /gsd:plan-phase, etc.) produce identical behavior after addon install as before
  3. A test suite runs and passes that verifies /init-gsd leaves ~/.claude/CLAUDE.md and ~/.claude/rules/ completely untouched
  4. A test suite runs and passes that verifies base GSD commands still function correctly after addon skills are installed
**Plans**: TBD

Plans:
- [ ] 10-01: TBD
- [ ] 10-02: TBD

## Progress

**Execution Order:** 09 -> 10

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 09. Local-First Install | v1.3 | 0/? | Not started | - |
| 10. Coexistence Validation | v1.3 | 0/? | Not started | - |
