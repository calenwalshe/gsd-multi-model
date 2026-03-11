---
phase: 03-entropy-management
plan: 02
subsystem: tooling
tags: [bash, git-blame, todo-tracking, entropy-detection]

requires:
  - phase: 02-deterministic-gates
    provides: gate-check.sh patterns (JSON stdout, stderr human output, config reading, test fixtures)
provides:
  - "bin/check-stale-todos.sh -- stale TODO/FIXME detector with git blame age tracking"
  - "bin/test-check-stale-todos.sh -- 9-test suite for TODO detection"
affects: [03-entropy-management, entropy-sweep orchestrator]

tech-stack:
  added: []
  patterns: [git-blame-porcelain-parsing, age-based-severity-classification]

key-files:
  created:
    - bin/check-stale-todos.sh
    - bin/test-check-stale-todos.sh
  modified: []

key-decisions:
  - "Used git blame -p (porcelain) for reliable machine-readable author-time extraction"
  - "Untracked files get age_days=0 instead of failing, for graceful new-file handling"
  - "Config thresholds read from .planning/config.json entropy.checks.stale_todos section with sensible defaults"

patterns-established:
  - "git blame porcelain parsing: grep author-time + cut for epoch extraction"
  - "Severity tiering: info < warn_days <= warning < critical_days <= critical"

requirements-completed: [ENTR-03]

duration: 2min
completed: 2026-03-11
---

# Phase 03 Plan 02: Stale TODO/FIXME Detector Summary

**Shell-based TODO/FIXME detector using git blame porcelain for age tracking with configurable warn/critical severity thresholds**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-11T18:50:14Z
- **Completed:** 2026-03-11T18:52:30Z
- **Tasks:** 1 (TDD: test + implement)
- **Files modified:** 2

## Accomplishments
- Built check-stale-todos.sh that finds TODO/FIXME across .sh/.js/.cjs/.ts/.md files
- Age computation via git blame porcelain author-time with UTC epoch arithmetic
- Severity classification (info/warning/critical) with configurable thresholds from config.json
- Graceful handling of untracked files (age_days=0)
- JSON stdout output compatible with entropy-sweep.sh orchestrator interface
- 9-test suite covering all behaviors including backdated commits and untracked files

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Failing tests** - `f464310` (test)
2. **Task 1 (GREEN): Implementation** - `343dd01` (feat)

_TDD task with RED/GREEN commits._

## Files Created/Modified
- `bin/check-stale-todos.sh` - Stale TODO/FIXME detector with git blame age tracking (234 lines)
- `bin/test-check-stale-todos.sh` - Test suite with 9 test cases using temp git repo fixtures (298 lines)

## Decisions Made
- Used git blame -p (porcelain format) for reliable, machine-readable date extraction
- Untracked files default to current timestamp (age_days=0) rather than erroring
- Config read from entropy.checks.stale_todos in .planning/config.json with defaults (30/90 days)
- Excluded .git, node_modules, .planning directories from scanning
- Exit code 0 = no findings, 1 = findings exist (consistent with gate-check.sh pattern)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- check-stale-todos.sh ready for integration into entropy-sweep.sh orchestrator (Plan 01/04)
- JSON output follows the interface spec defined in the plan
- Config.json entropy section not yet created (will be added by Plan 04)

---
*Phase: 03-entropy-management*
*Completed: 2026-03-11*
