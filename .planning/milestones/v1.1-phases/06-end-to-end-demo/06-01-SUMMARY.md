---
phase: 06-end-to-end-demo
plan: 01
subsystem: testing
tags: [shell, demo, e2e, worktree, codex, dry-run]

requires:
  - phase: 04-worktree-automation
    provides: worktree-create.sh and worktree-cleanup.sh for isolated execution
  - phase: 05-codex-execution-wrapper
    provides: codex-task.sh for task parsing and Codex CLI invocation

provides:
  - bin/demo.sh end-to-end workflow demo script
  - test/fixtures/demo-project/ fixture project with PLAN.md and source files
  - bin/test-demo.sh test suite for demo script

affects: []

tech-stack:
  added: []
  patterns:
    - "Inter-stage state sharing via temp files (save_state/source pattern)"
    - "Stage execution engine with timing, artifact tracking, and abort-on-fail"

key-files:
  created:
    - bin/demo.sh
    - bin/test-demo.sh
    - test/fixtures/demo-project/package.json
    - test/fixtures/demo-project/src/utils.js
    - test/fixtures/demo-project/.planning/phases/01-add-utils/01-01-PLAN.md
  modified: []

key-decisions:
  - "Simulate init-gsd bootstrap (it is a Claude Code skill, not a standalone script)"
  - "Use temp file for inter-stage state sharing to avoid subshell variable loss"
  - "Pre-clean worktree artifacts from /tmp to handle reruns gracefully"

patterns-established:
  - "Stage execution engine: run_stage with timing, artifacts, and fail-fast"
  - "Fixture projects in test/fixtures/ for integration testing"

requirements-completed: [DEMO-01, DEMO-02]

duration: 6min
completed: 2026-03-03
---

# Phase 6 Plan 1: End-to-End Demo Summary

**7-stage demo script proving full GSD dual-tool workflow loop: bootstrap, plan validation, task splitting, worktree creation, codex execution (dry-run), cleanup, and cross-review**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-03T06:09:56Z
- **Completed:** 2026-03-03T06:16:05Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Created fixture project with PLAN.md containing XML task blocks for codex/claude executor routing
- Built bin/demo.sh with 7 sequential stages, pre-flight checks, and summary table output
- Supports --dry-run (default), --live, --keep, and --json flags
- Test suite with 15 passing tests covering all modes and cleanup

## Task Commits

Each task was committed atomically:

1. **Task 1: Create fixture project** - `8f98537` (feat)
2. **Task 2: Create bin/demo.sh (RED)** - `3629bae` (test)
3. **Task 2: Create bin/demo.sh (GREEN)** - `e8d88af` (feat)

**Plan metadata:** [pending] (docs: complete plan)

_Note: TDD task has separate RED/GREEN commits_

## Files Created/Modified
- `bin/demo.sh` - End-to-end demo script with 7 stages, pre-flight, sandbox, and summary table
- `bin/test-demo.sh` - Test suite with 15 tests for demo.sh
- `test/fixtures/demo-project/package.json` - Minimal package.json for stack detection
- `test/fixtures/demo-project/src/utils.js` - Source file with TODO for Codex task
- `test/fixtures/demo-project/.planning/phases/01-add-utils/01-01-PLAN.md` - PLAN.md with 2 XML task blocks

## Decisions Made
- Simulated init-gsd bootstrap since it is a Claude Code skill (not a standalone script)
- Used temp files for inter-stage state sharing to avoid subshell variable scoping issues
- Added pre-cleanup of /tmp worktree artifacts to handle reruns gracefully
- Worktree cleanup uses --no-merge --force (demo worktree has no real changes to merge)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed inter-stage variable sharing**
- **Found during:** Task 2 (demo.sh creation)
- **Issue:** Stage functions run inside run_stage which captured stdout via $(), creating a subshell that lost variable assignments (WORKTREE_BRANCH, CODEX_JSON_OUTPUT)
- **Fix:** Introduced temp file state sharing pattern (save_state/source) and set_artifacts helper
- **Files modified:** bin/demo.sh
- **Verification:** All 7 stages pass including worktree cleanup (which depends on WORKTREE_BRANCH from stage 4)
- **Committed in:** e8d88af

**2. [Rule 3 - Blocking] Added worktree artifact pre-cleanup**
- **Found during:** Task 2 (demo.sh creation)
- **Issue:** Failed reruns left /tmp/gsd-worktree-phase01-plan01 behind, causing subsequent runs to fail at worktree creation
- **Fix:** Added pre-cleanup of known worktree paths and cleanup trap for worktree artifacts
- **Files modified:** bin/demo.sh
- **Verification:** Demo runs cleanly on repeated invocations
- **Committed in:** e8d88af

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both fixes were necessary for correct operation. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviations above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Demo proves all components work together end-to-end
- Phase 6 Plan 2 (if any) can build on this foundation
- Ready for final milestone verification

---
*Phase: 06-end-to-end-demo*
*Completed: 2026-03-03*
