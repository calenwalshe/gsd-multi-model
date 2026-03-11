---
phase: 01
slug: the-orchestrator
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-11
---

# Phase 01 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + manual verification |
| **Config file** | none — SKILL.md is a markdown spec, not executable code |
| **Quick run command** | `bash test-install.sh` |
| **Full suite command** | Manual: run `/gsd:drive` in a test project |
| **Estimated runtime** | ~30 seconds (install test), ~5 min (manual drive test) |

---

## Sampling Rate

- **After every task commit:** Run `bash test-install.sh`
- **After every plan wave:** Manual `/gsd:drive` test on a scratch project
- **Before `/gsd:verify-work`:** Full `/gsd:drive` run through at least one phase lifecycle
- **Max feedback latency:** 30 seconds (automated), 5 min (manual)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | ORCH-01 | integration (manual) | Run `/gsd:drive` on fresh phase | ❌ W0 | ⬜ pending |
| 01-01-02 | 01 | 1 | ORCH-04 | integration (manual) | Interrupt drive, re-run, verify resume | ❌ W0 | ⬜ pending |
| 01-02-01 | 02 | 1 | ORCH-02 | smoke (manual) | Verify no `/clear` in output | ❌ W0 | ⬜ pending |
| 01-02-02 | 02 | 1 | ORCH-03 | smoke (manual) | Run drive, confirm no unnecessary pauses | ❌ W0 | ⬜ pending |
| 01-03-01 | 03 | 1 | ORCH-05 | unit (bash) | `bash bin/test-drive-args.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `skills/gsd-drive/SKILL.md` — the skill file itself (primary deliverable)
- [ ] `bin/test-drive-args.sh` — argument parsing tests for --phase and --to flags
- [ ] Update `test-install.sh` — verify gsd-drive skill installs correctly
- [ ] Update `bin/cli.sh` — include gsd-drive in skill installation

*Note: Most validation is manual because the deliverable is a markdown prompt spec, not executable code.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Full chain: discuss→plan→execute→verify→advance | ORCH-01 | Requires live Claude Code session | Run `/gsd:drive` on a project with unplanned phase, observe full chain |
| Internal context resets | ORCH-02 | Requires observing context window behavior | Drive through 2+ phases, verify no `/clear` prompts |
| Smart pausing | ORCH-03 | Requires judgment about "genuine ambiguity" | Run drive, verify it only stops for external actions |
| Resume after interruption | ORCH-04 | Requires simulating crash/abort | Kill session mid-drive, re-run `/gsd:drive`, verify correct resume |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s (automated)
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
