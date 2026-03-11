# Milestones

## v1.2 Upstream Sync (Shipped: 2026-03-06)

**Phases completed:** 2 phases, 2 plans
**Timeline:** 2026-03-06 (single day)

**Key accomplishments:**
1. Version pinning with `gsd-compat.json` tested range manifest
2. Install-time compatibility check with warn-only behavior
3. Update wrapper (`gsd-update.sh`) with three-stage pipeline and structured exit codes

---

## v1.1 Execution-Side Integration (Shipped: 2026-03-05)

**Phases completed:** 4 phases, 9 plans, 18 tasks
**Timeline:** 2026-03-02 to 2026-03-05 (2 days)
**Files changed:** 77 files, 14,484 lines added
**Production code:** 4,504 LOC (bash)

**Key accomplishments:**
1. Hardened `install.sh` with pre-flight dependency checks, integrity validation, ANSI output, and `--force` flag
2. Built worktree automation (`worktree-create.sh`, `worktree-cleanup.sh`, `worktree-list.sh`) for isolated parallel Codex execution with JSON output
3. Created Codex execution wrapper (`codex-task.sh`) with shell-only XML parsing, confidence-based routing, structured JSON output, and exit code contract (0-4)
4. Shipped end-to-end demo (`demo.sh`) proving full dual-tool workflow loop in 7 stages with dry-run/live modes
5. Comprehensive test suites for all scripts: `test-install.sh`, `test-codex-task.sh`, `test-demo.sh` (37+ test cases total)

---

## v1.0 Dual-Tool Framework MVP (Shipped: 2026-03-02)

**Phases completed:** 2 phases, 5 plans, 6 tasks
**Timeline:** 2026-03-02 (single day)
**Files changed:** 31 files, 7,173 lines added

**Key accomplishments:**
1. Production-grade `/init-gsd` skill with 10-step bootstrap, idempotency, stack detection for 5 ecosystems (479 lines)
2. `/codex-review` skill with 7-step sequential execution, Codex CLI invocation, and bidirectional review
3. `/gsd-codex-verify` skill with dual verification gate, JSONL parsing, and structured PASS/FAIL reports (385 lines)
4. 4-signal task routing heuristic embedded in gsd-planner (scope, clarity, isolation, error cost) with compound keyword type shortcuts
5. PLAN.md XML schema extended with `executor` and `confidence` attributes for Claude/Codex routing
6. Plan checker Dimension 9 added for routing validation with Phase 1 backward compatibility

---

## v1.3 Safe Local-First Install (Superseded: 2026-03-11)

**Status:** Superseded by v2.0
**Reason:** The npx-based `bin/cli.sh` approach (built during v2.0 planning) achieves zero-risk install without project-scoped config complexity. Local-first goals are fully covered by the skills-only default install mode.

---
