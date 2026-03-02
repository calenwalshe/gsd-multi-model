# Roadmap — gsd-multi-model

## Milestone 1: Dual-Tool Framework MVP

### Phase 1: Core Skill Implementation
**Goal**: Implement the three custom skills that are currently spec-only
**Requirements**: R1, R2, R3
**Effort**: Large
**Plans:** 3 plans

Plans:
- [ ] 01-01-PLAN.md — Rewrite /init-gsd SKILL.md with production-grade idempotency, stack detection, error handling
- [ ] 01-02-PLAN.md — Rewrite /codex-review SKILL.md with Codex invocation, severity reporting, bidirectional review
- [ ] 01-03-PLAN.md — Rewrite /gsd-codex-verify SKILL.md with dual verification, JSONL parsing, VERIFICATION.md output

**Deliverables**:
- `/init-gsd` skill with full project bootstrapping logic
- `/codex-review` skill with Codex invocation and output capture
- `/gsd-codex-verify` skill with combined verification pipeline
- All skills functional in Claude Code sessions

**Success Criteria**:
- Each skill executes end-to-end without errors
- `/init-gsd` creates complete project scaffold
- `/codex-review` successfully invokes Codex and returns review
- `/gsd-codex-verify` produces structured PASS/FAIL report

---

### Phase 2: Task Splitting & Routing
**Goal**: Implement heuristic-based task classification for Claude vs Codex
**Requirements**: R4
**Effort**: Medium

**Deliverables**:
- Task classification engine (rule-based heuristic)
- PLAN.md XML schema extension with `executor` attribute
- Override mechanism for user corrections
- Integration with /gsd:plan-phase output

**Success Criteria**:
- Tasks auto-tagged with correct executor based on signals
- Multi-file/architecture tasks → Claude
- CRUD/tests/scripts → Codex
- User overrides persist and are respected during execution

---

### Phase 3: Worktree & Codex Execution
**Goal**: Automate parallel Codex execution via git worktrees
**Requirements**: R5, R6
**Effort**: Medium

**Deliverables**:
- `bin/codex-task.sh` execution wrapper
- Worktree lifecycle management (create → execute → verify → merge → cleanup)
- JSONL output capture and parsing
- Protected-path verification

**Success Criteria**:
- Codex tasks execute in isolated worktrees
- JSONL output captured and errors surfaced
- Successful tasks merge back cleanly
- Failed tasks leave worktree for manual inspection
- No modifications to .planning/ or .git/ by Codex

---

### Phase 4: Cross-Model Verification
**Goal**: Wire up the full cross-review loop
**Requirements**: R2, R3 (integration)
**Effort**: Small

**Deliverables**:
- Claude reviews Codex worktree output against PLAN.md specs
- Codex reviews Claude's changes for blind spots
- Combined report with per-task pass/fail
- Feedback loop: failed verification creates new fix tasks

**Success Criteria**:
- Cross-review catches intentionally introduced bugs
- Combined report clearly shows what passed and what failed
- Fix tasks generated automatically for failures

---

### Phase 5: End-to-End Integration & Demo
**Goal**: Validate the complete workflow and harden the installer
**Requirements**: R7, R8, R9
**Effort**: Medium

**Deliverables**:
- End-to-end demo project exercising full loop
- Updated install.sh with dependency checks
- Updated test-install.sh covering all new components
- README/docs showing the workflow in action

**Success Criteria**:
- Full loop: /init-gsd → plan → auto-split → Codex builds → cross-review → pass
- Installer handles missing deps gracefully
- All tests pass on clean install
- Demo is reproducible

---

## Phase Dependencies

```
Phase 1 (Skills) ──→ Phase 2 (Splitting) ──→ Phase 3 (Worktrees)
                                                    │
                                                    ▼
                                              Phase 4 (Cross-Review)
                                                    │
                                                    ▼
                                              Phase 5 (Integration)
```

## Requirement Coverage

| Requirement | Phase(s) |
|-------------|----------|
| R1: /init-gsd | Phase 1 |
| R2: /codex-review | Phase 1, Phase 4 |
| R3: /gsd-codex-verify | Phase 1, Phase 4 |
| R4: Task splitting | Phase 2 |
| R5: Worktree automation | Phase 3 |
| R6: Codex wrapper | Phase 3 |
| R7: E2E demo | Phase 5 |
| R8: Installer hardening | Phase 5 |
| R9: Global configs | Phase 5 |
