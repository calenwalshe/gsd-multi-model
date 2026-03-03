---
phase: 05-codex-execution-wrapper
plan: 01
subsystem: cli
tags: [bash, codex, worktree, xml-parsing, task-runner]

requires:
  - phase: 04-worktree-automation
    provides: worktree-create.sh and worktree-cleanup.sh for isolated execution
provides:
  - bin/codex-task.sh — Codex CLI wrapper with XML task parsing, context injection, worktree lifecycle, structured JSON output
affects: [06-e2e-demo]

tech-stack:
  added: []
  patterns: [XML task extraction via awk/grep/sed, confidence-based routing, structured JSON output with stderr summary]

key-files:
  created:
    - bin/codex-task.sh
    - bin/test-codex-task.sh
  modified: []

key-decisions:
  - "Shell-only XML parsing with awk/grep/sed — no external parser dependencies"
  - "Confidence routing: high=--full-auto, medium=default approval, low=skip with warning"
  - "Keep worktree on Codex failure (discard without merge) for debugging"
  - "Temp files for prompt, stdout, stderr capture with cleanup on exit"

patterns-established:
  - "Codex invocation pattern: build prompt file, run in worktree, auto-commit, merge back"
  - "Exit code contract extended: 0=success, 1=codex failure, 2=parse error, 3=timeout, 4=pre-flight"

requirements-completed: [CODEX-01, CODEX-02, CODEX-03]

duration: 4min
completed: 2026-03-03
---

# Phase 5 Plan 01: Codex Execution Wrapper Summary

**Codex CLI wrapper script with XML task parsing, worktree isolation, confidence routing, and structured JSON output**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-03T05:12:44Z
- **Completed:** 2026-03-03T05:16:26Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Full Codex task execution lifecycle: parse plan -> create worktree -> inject context -> invoke Codex -> commit -> report -> cleanup
- XML task extraction correctly handles all PLAN.md files (multi-line action blocks, multiple attributes, tdd/executor/confidence)
- 9-section script (542 lines) with comprehensive pre-flight checks and structured error handling
- All 9 tests pass including dry-run JSON validation, task extraction, and exit code verification

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Failing tests for codex-task.sh** - `646d1c7` (test)
2. **Task 1 (GREEN): Implement codex-task.sh** - `2f94f2a` (feat)
3. **Task 2: Verify parsing and dry-run** - no commit (verification-only task, no changes needed)

## Files Created/Modified
- `bin/codex-task.sh` - Codex execution wrapper (542 lines, 9 sections)
- `bin/test-codex-task.sh` - Test suite with 9 test cases

## Decisions Made
- Shell-only XML parsing with awk/grep/sed for zero external dependencies
- Confidence routing: high triggers --full-auto, medium uses default approval, low warns and exits
- On Codex failure: worktree is discarded (--no-merge --force) rather than kept
- Prompt built from task action + done criteria + files_modified + CLAUDE.md + AGENTS.md

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- bin/codex-task.sh ready for Phase 6 E2E demo consumption
- Script integrates with Phase 4 worktree scripts (create/cleanup)
- Dry-run mode works without Codex installed (useful for testing)

---
*Phase: 05-codex-execution-wrapper*
*Completed: 2026-03-03*
