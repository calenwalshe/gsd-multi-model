# Requirements: gsd-multi-model

**Defined:** 2026-03-02
**Core Value:** Structured dual-tool workflow that splits work by tool strengths automatically

## v1.1 Requirements

Requirements for execution-side integration. Each maps to roadmap phases.

### Worktree Automation

- [ ] **WKTREE-01**: `bin/worktree-create.sh` creates isolated git worktree for Codex execution
- [ ] **WKTREE-02**: `bin/worktree-cleanup.sh` removes worktree and merges changes back
- [ ] **WKTREE-03**: Worktree scripts handle branch naming, conflict detection, and error cases

### Codex Execution

- [ ] **CODEX-01**: `bin/codex-task.sh` wraps Codex CLI invocation with task context injection
- [ ] **CODEX-02**: Codex runner reads executor attributes from PLAN.md task XML
- [ ] **CODEX-03**: Codex runner produces structured output (exit code, changed files, commit hash)

### End-to-End Demo

- [ ] **DEMO-01**: Demo script runs full workflow: init → plan → split → parallel execute → cross-review
- [ ] **DEMO-02**: Demo validates each stage completed successfully before advancing

### Installer Hardening

- [ ] **INST-01**: `install.sh` checks for required dependencies (Claude Code, git, node) before installing
- [ ] **INST-02**: `install.sh` validates installed file integrity after copy
- [ ] **INST-03**: `install.sh` provides clear error messages with resolution steps for missing deps

### Global Config

- [ ] **CONF-01**: Global Claude Code config template installed to `~/.claude/` with dual-tool defaults
- [ ] **CONF-02**: Global Codex config template installed with `--full-auto` and approval settings
- [ ] **CONF-03**: Config templates are non-destructive (skip if user config already exists)

## v1.0 Requirements (Shipped)

### Skills

- [x] **SKILL-01**: `/init-gsd` bootstrap with idempotency, stack detection, full project scaffolding
- [x] **SKILL-02**: `/codex-review` cross-model review with Codex invocation and severity reporting
- [x] **SKILL-03**: `/gsd-codex-verify` dual verification gate with JSONL parsing and structured reports

### Task Routing

- [x] **ROUTE-01**: 4-signal task routing heuristic with type shortcuts and user overrides
- [x] **ROUTE-02**: PLAN.md XML schema extended with executor and confidence attributes
- [x] **ROUTE-03**: Plan checker Dimension 9 for routing validation

## Out of Scope

| Feature | Reason |
|---------|--------|
| Gemini/OpenCode integration | Claude + Codex only |
| Mobile/web UI | CLI-first approach |
| Cloud hosting | Local development tool |
| Real-time streaming from Codex | Codex CLI handles its own output |
| Custom model routing | Fixed Claude/Codex split is sufficient |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| WKTREE-01 | TBD | Pending |
| WKTREE-02 | TBD | Pending |
| WKTREE-03 | TBD | Pending |
| CODEX-01 | TBD | Pending |
| CODEX-02 | TBD | Pending |
| CODEX-03 | TBD | Pending |
| DEMO-01 | TBD | Pending |
| DEMO-02 | TBD | Pending |
| INST-01 | TBD | Pending |
| INST-02 | TBD | Pending |
| INST-03 | TBD | Pending |
| CONF-01 | TBD | Pending |
| CONF-02 | TBD | Pending |
| CONF-03 | TBD | Pending |

**Coverage:**
- v1.1 requirements: 14 total
- Mapped to phases: 0 (pending roadmap)
- Unmapped: 14 ⚠️

---
*Requirements defined: 2026-03-02*
*Last updated: 2026-03-02 after v1.1 milestone start*
