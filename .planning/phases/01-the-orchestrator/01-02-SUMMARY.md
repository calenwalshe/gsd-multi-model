---
phase: 01-the-orchestrator
plan: 02
subsystem: orchestration
tags: [workflows, auto-advance, gsd-drive, phase-chaining]

# Dependency graph
requires:
  - phase: none
    provides: existing workflow files with --auto mechanism
provides:
  - "--auto flag removed from all four workflow files"
  - "clean termination at offer_next in each workflow"
  - "yolo mode routes to /gsd:drive instead of --auto Skill() calls"
affects: [01-the-orchestrator, gsd-drive]

# Tech tracking
tech-stack:
  added: []
  patterns: ["/gsd:drive as single auto-chaining entry point"]

key-files:
  created:
    - global/workflows/discuss-phase.md
    - global/workflows/plan-phase.md
    - global/workflows/execute-phase.md
    - global/workflows/transition.md
  modified:
    - ~/.claude/get-shit-done/workflows/discuss-phase.md
    - ~/.claude/get-shit-done/workflows/plan-phase.md
    - ~/.claude/get-shit-done/workflows/execute-phase.md
    - ~/.claude/get-shit-done/workflows/transition.md

key-decisions:
  - "Hard cut of --auto flag -- v2.0 breaking change, /gsd:drive replaces all auto-chaining"
  - "Replaced removed sections with HTML comments for traceability"

patterns-established:
  - "Workflow files end at offer_next or equivalent user-facing output"
  - "/gsd:drive is the sole entry point for automated phase chaining"

requirements-completed: [ORCH-01]

# Metrics
duration: 4min
completed: 2026-03-11
---

# Phase 01 Plan 02: Remove --auto Flag Summary

**Hard cut of --auto flag mechanism from all workflow files -- /gsd:drive replaces auto-chaining as v2.0 breaking change**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-11T07:28:58Z
- **Completed:** 2026-03-11T07:33:02Z
- **Tasks:** 2
- **Files modified:** 8 (4 installed + 4 repo copies)

## Accomplishments
- Removed auto_advance step, --auto flag parsing, _auto_chain_active config reads, and AUTO_CHAIN/AUTO_CFG variables from discuss-phase.md, plan-phase.md, execute-phase.md
- Updated transition.md yolo mode to recommend /gsd:drive instead of Skill() --auto calls
- Removed _auto_chain_active config-set at milestone boundary in transition.md
- All workflow files terminate cleanly at user-facing output steps

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove --auto from discuss/plan/execute** - `4939dd5` (feat)
2. **Task 2: Update transition.md to route to /gsd:drive** - `ce1cf66` (feat)

## Files Created/Modified
- `global/workflows/discuss-phase.md` - Removed auto_advance step (lines 589-658)
- `global/workflows/plan-phase.md` - Removed Step 14 auto_advance, updated Step 13 routing
- `global/workflows/execute-phase.md` - Removed --auto sync, AUTO_CHAIN/AUTO_CFG checkpoint reads, auto_advance in offer_next
- `global/workflows/transition.md` - Replaced yolo --auto Skill() calls with /gsd:drive, removed _auto_chain_active config-set

## Decisions Made
- Hard cut per locked decision: anyone using --auto should switch to /gsd:drive
- Replaced removed sections with HTML comments for discoverability (e.g., `<!-- auto_advance removed in v2.0 -- use /gsd:drive for auto-chaining -->`)
- Created repo copies in global/workflows/ for version control since installed files are outside repo

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Workflow files are clean of --auto mechanism
- Ready for /gsd:drive implementation (Plan 01-01 or 01-03) to provide the replacement auto-chaining

---
*Phase: 01-the-orchestrator*
*Completed: 2026-03-11*
