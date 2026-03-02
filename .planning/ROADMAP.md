# Roadmap: gsd-multi-model

## Milestones

- [x] **v1.0 Dual-Tool Framework MVP** - Phases 1-2 (shipped 2026-03-02)
- [ ] **v1.1 Execution-Side Integration** - Phases 3-6 (in progress)

## Phases

<details>
<summary>v1.0 Dual-Tool Framework MVP (Phases 1-2) - SHIPPED 2026-03-02</summary>

- [x] Phase 1: Core Skill Implementation (3/3 plans) - completed 2026-03-02
- [x] Phase 2: Task Splitting & Routing (2/2 plans) - completed 2026-03-02

See: `.planning/milestones/v1.0-ROADMAP.md` for full details

</details>

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (3.1, 3.2): Urgent insertions (marked with INSERTED)

### v1.1 Execution-Side Integration

- [ ] **Phase 3: Installer Hardening & Global Config** - Dependency checks, integrity validation, and config templates for Claude/Codex
- [ ] **Phase 4: Worktree Automation** - Isolated git worktree lifecycle for parallel Codex execution
- [ ] **Phase 5: Codex Execution Wrapper** - Task runner that invokes Codex CLI with context injection and structured output
- [ ] **Phase 6: End-to-End Demo** - Full workflow proof: init to plan to split to parallel execute to cross-review

## Phase Details

### Phase 3: Installer Hardening & Global Config
**Goal**: Users get reliable installation with clear feedback and sensible defaults for both tools
**Depends on**: Phase 2 (v1.0 shipped)
**Requirements**: INST-01, INST-02, INST-03, CONF-01, CONF-02, CONF-03
**Success Criteria** (what must be TRUE):
  1. Running `install.sh` on a machine missing Claude Code or git produces a clear error naming the missing dependency and how to install it
  2. Running `install.sh` on a properly equipped machine completes and all installed files match their sources
  3. Running `install.sh` installs global Claude config with dual-tool defaults to `~/.claude/` without overwriting existing user config
  4. Running `install.sh` installs global Codex config with `--full-auto` defaults without overwriting existing user config
**Plans**: 2 plans

Plans:
- [ ] 03-01-PLAN.md — Harden install.sh with pre-flight checks, integrity validation, ANSI output, --force flag, unified config strategy
- [ ] 03-02-PLAN.md — Upgrade test-install.sh with diff-based integrity checks

### Phase 4: Worktree Automation
**Goal**: Users can create and tear down isolated git worktrees for parallel Codex work with a single command
**Depends on**: Phase 3
**Requirements**: WKTREE-01, WKTREE-02, WKTREE-03
**Success Criteria** (what must be TRUE):
  1. Running `bin/worktree-create.sh` from a git repo creates a new worktree on a uniquely named branch, ready for Codex to work in
  2. Running `bin/worktree-cleanup.sh` removes the worktree directory and branch, merging changes back to the source branch
  3. Worktree scripts detect and abort on conflicts (dirty working tree, existing branch name, merge conflicts) with actionable error messages
**Plans**: TBD

Plans:
- [ ] 04-01: TBD

### Phase 5: Codex Execution Wrapper
**Goal**: Users can dispatch a planned task to Codex CLI and get back structured results
**Depends on**: Phase 4
**Requirements**: CODEX-01, CODEX-02, CODEX-03
**Success Criteria** (what must be TRUE):
  1. Running `bin/codex-task.sh` with a PLAN.md task reference invokes Codex CLI with the task description and relevant file context injected
  2. The runner reads executor attributes (tool assignment, confidence) from PLAN.md XML task blocks to configure the Codex invocation
  3. After Codex completes, the runner outputs a structured report: exit code, list of changed files, and commit hash
**Plans**: TBD

Plans:
- [ ] 05-01: TBD

### Phase 6: End-to-End Demo
**Goal**: A single demo proves the full dual-tool workflow loop runs without manual intervention beyond initial project decisions
**Depends on**: Phase 5
**Requirements**: DEMO-01, DEMO-02
**Success Criteria** (what must be TRUE):
  1. Running the demo script executes the full loop: `/init-gsd` bootstrap, plan creation, task splitting, parallel Codex execution in worktree, and cross-review
  2. The demo script validates each stage completed successfully (non-zero exit on failure) before advancing to the next stage
  3. After demo completes, the user sees a summary showing which stages passed and what artifacts were produced
**Plans**: TBD

Plans:
- [ ] 06-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 3 -> 4 -> 5 -> 6

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Core Skill Implementation | v1.0 | 3/3 | Complete | 2026-03-02 |
| 2. Task Splitting & Routing | v1.0 | 2/2 | Complete | 2026-03-02 |
| 3. Installer Hardening & Global Config | v1.1 | 0/2 | Planning complete | - |
| 4. Worktree Automation | v1.1 | 0/? | Not started | - |
| 5. Codex Execution Wrapper | v1.1 | 0/? | Not started | - |
| 6. End-to-End Demo | v1.1 | 0/? | Not started | - |
