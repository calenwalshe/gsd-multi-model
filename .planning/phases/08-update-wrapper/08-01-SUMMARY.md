---
phase: 08-update-wrapper
plan: 01
subsystem: infra
tags: [bash, npx, update, semver, exit-codes, pipeline]

# Dependency graph
requires:
  - phase: 07-compatibility-manifest-install-time-check
    provides: "gsd-compat.json manifest, semver_compare() function, compat_check() pattern"
provides:
  - "bin/gsd-update.sh -- single-command GSD update + addon reinstall + compat verification"
  - "bin/test-gsd-update.sh -- structural, unit, and mock-based test suite"
  - "Structured exit code contract: 0=success, 1=GSD fail, 2=install fail, 3=compat warning"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Three-stage pipeline with || RC=$? exit code capture under set -euo pipefail"
    - "Mock-based testing via PATH override and temp directory mirroring repo layout"
    - "Old->new version comparison reporting for user-facing update scripts"

key-files:
  created:
    - bin/gsd-update.sh
    - bin/test-gsd-update.sh
  modified: []

key-decisions:
  - "Inline semver_compare in gsd-update.sh rather than sourcing install.sh (avoids side effects)"
  - "install.sh style ANSI helpers (checkmark/warning/cross on stdout) not codex-task.sh style (text labels on stderr)"
  - "Mock npx via PATH prepend, mock install.sh via temp directory mirroring repo layout"

patterns-established:
  - "bin/ update scripts: three-stage pipeline with structured exit codes and || RC=$? guards"
  - "Mock-based exit code testing: setup_mock_env/create_mock_*/cleanup_mock_env pattern"

requirements-completed: [UPDT-01, UPDT-02, UPDT-03]

# Metrics
duration: 2 min
completed: 2026-03-06
---

# Phase 8 Plan 1: Update Wrapper Summary

**bin/gsd-update.sh three-stage pipeline (npx update, addon reinstall, compat verification) with structured exit codes 0/1/2/3 and 19-test suite**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-06T21:39:55Z
- **Completed:** 2026-03-06T21:42:32Z
- **Tasks:** 3
- **Files created:** 2

## Accomplishments
- Created bin/gsd-update.sh (164 lines) chaining npx update, install.sh --force, and compat verification
- Structured exit codes: 0=success, 1=GSD update failed, 2=addon reinstall failed, 3=compat warning
- Old-to-new version transition reporting (e.g., "Updated: v1.22.4 -> v1.23.0")
- Created bin/test-gsd-update.sh (257 lines) with 19 tests: 9 structural, 6 semver unit, 4 mock-based exit code
- All 19 tests pass with 0 failures

## Task Commits

Each task was committed atomically:

1. **Task 1: Create bin/gsd-update.sh with three-stage pipeline** - `19293c9` (feat)
2. **Task 2: Create bin/test-gsd-update.sh test suite** - `9971578` (test)
3. **Task 3: Run test suite and verify all tests pass** - no commit (verification only, all passed)

## Files Created/Modified
- `bin/gsd-update.sh` - Three-stage update wrapper: npx GSD update, install.sh --force reinstall, semver compat verification
- `bin/test-gsd-update.sh` - Test suite: structural tests, semver_compare unit tests, mock-based exit code tests

## Decisions Made
- Inlined semver_compare() in gsd-update.sh rather than sourcing from install.sh, avoiding side effects from set -euo pipefail and install-time code
- Used install.sh style ANSI helpers (checkmark/warning/cross characters, stdout output, TTY detection on fd 1) since the update wrapper is user-facing
- Mock-based testing uses PATH prepend for npx and temp directory with copied gsd-update.sh for full isolation

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 8 complete (single plan), milestone v1.2 complete
- bin/gsd-update.sh ready for use: `bash bin/gsd-update.sh` from the gsd-multi-model repo
- All v1.2 requirements delivered: COMPAT-01, COMPAT-02, COMPAT-03 (Phase 7), UPDT-01, UPDT-02, UPDT-03 (Phase 8)

---
*Phase: 08-update-wrapper*
*Completed: 2026-03-06*
