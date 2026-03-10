# Requirements: gsd-multi-model

**Defined:** 2026-03-08
**Core Value:** Structured dual-tool workflow that splits work by tool strengths automatically

## v1.3 Requirements

Requirements for Safe Local-First Install. Each maps to roadmap phases.

### Install

- [ ] **INST-01**: `/init-gsd` creates project-local `CLAUDE.md` with dual-tool workflow instructions (not `~/.claude/CLAUDE.md`)
- [ ] **INST-02**: `/init-gsd` creates project-local `.claude/rules/` with dual-tool rules (not `~/.claude/rules/`)
- [ ] **INST-03**: `/init-gsd` configures bin/ script references as absolute paths to the cloned gsd-multi-model repo
- [ ] **INST-04**: `/init-gsd` detects existing base GSD and skips global modifications

### Coexistence

- [ ] **COEX-01**: Addon skills (`init-gsd`, `codex-review`, `gsd-codex-verify`) install globally without colliding with base GSD `/gsd:*` commands
- [ ] **COEX-02**: Running `/init-gsd` in a project does not modify `~/.claude/CLAUDE.md` or `~/.claude/rules/`
- [ ] **COEX-03**: Base GSD commands (`/gsd:progress`, `/gsd:plan-phase`, etc.) continue working unchanged after addon skills are installed

### Validation

- [ ] **VALID-01**: Test suite verifies local-only install leaves global config untouched
- [ ] **VALID-02**: Test suite verifies base GSD commands still function after addon install

## Future Requirements

### Cleanup

- **CLEAN-01**: Uninstall/cleanup command to remove per-project setup
- **CLEAN-02**: Refactor global installer to support both local and global modes cleanly

## Out of Scope

| Feature | Reason |
|---------|--------|
| Renaming addon skills to a different namespace | Skills already have unique names that don't collide with base GSD |
| Global installer refactor | v1.3 focuses on local install only; global installer works as-is |
| Uninstall command | Defer to future -- manual cleanup is fine for now |
| Runtime version checking | Already decided in v1.2 -- install-time only |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INST-01 | Phase 09 | Pending |
| INST-02 | Phase 09 | Pending |
| INST-03 | Phase 09 | Pending |
| INST-04 | Phase 09 | Pending |
| COEX-01 | Phase 10 | Pending |
| COEX-02 | Phase 09 | Pending |
| COEX-03 | Phase 10 | Pending |
| VALID-01 | Phase 10 | Pending |
| VALID-02 | Phase 10 | Pending |

**Coverage:**
- v1.3 requirements: 9 total
- Mapped to phases: 9
- Unmapped: 0

---
*Requirements defined: 2026-03-08*
*Last updated: 2026-03-08 after roadmap creation*
