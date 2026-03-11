---
phase: 02-task-splitting-routing
plan: 01
subsystem: planning
tags: [task-routing, heuristic, executor, codex, planner]

requires:
  - phase: 01-core-skill-implementation
    provides: "GSD framework skills (init-gsd, codex-review, gsd-codex-verify)"
provides:
  - "Task routing heuristic in gsd-planner.md"
  - "Extended PLAN.md schema with executor and confidence attributes"
  - "Routing summary table format for plan output"
affects: [03-worktree-parallel-execution, 04-smart-context-management]

tech-stack:
  added: []
  patterns: [task-routing-heuristic, 4-signal-analysis, compound-keyword-matching]

key-files:
  created: []
  modified:
    - "~/.claude/agents/gsd-planner.md"
    - "~/.claude/get-shit-done/templates/phase-prompt.md"

key-decisions:
  - "Compound verb+noun patterns for type shortcuts to avoid false positives on single words"
  - "Conservative default: 2 or fewer Codex-safe signals routes to Claude"
  - "Revision mode preserves user-overridden executor attributes"

patterns-established:
  - "4-signal analysis: scope, clarity, isolation, error cost for task routing"
  - "Checkpoint tasks always route to Claude regardless of other signals"

requirements-completed: [R4]

duration: 3min
completed: 2026-03-02
---

# Phase 2 Plan 1: Task Routing Heuristic Summary

**4-step task routing heuristic embedded in gsd-planner with compound keyword matching, 4-signal fallback analysis, and conservative Claude default for ambiguous tasks**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-02T05:46:12Z
- **Completed:** 2026-03-02T05:49:22Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Embedded `<task_routing>` section in gsd-planner.md with full 4-step classification heuristic (75 lines, under 120 limit)
- Extended phase-prompt.md task element schema with executor and confidence attributes across all examples
- Added backward-compatibility note for pre-Phase-2 plans without executor attributes

## Task Commits

Each task was committed atomically:

1. **Task 1: Add task_routing section to gsd-planner.md** - `58c472a` (feat)
2. **Task 2: Extend PLAN.md task element schema in phase-prompt.md** - `58c472a` (feat)

Note: Both tasks committed together as modified files are outside the git repo (GSD framework files at ~/.claude/).

## Files Created/Modified
- `~/.claude/agents/gsd-planner.md` - Added <task_routing> section with checkpoint pre-check, type shortcuts, 4-signal analysis, routing summary, revision override preservation, and anti-patterns
- `~/.claude/get-shit-done/templates/phase-prompt.md` - Added executor/confidence to task element template, checkpoint examples, autonomous/checkpoint examples, task-level attribute docs, backward-compat note, missing-executor anti-pattern

## Decisions Made
- Used compound verb+noun patterns (e.g., "write tests", "create script") rather than single keywords to avoid false positives where a word like "test" appears in unrelated context
- Conservative default: when only 2 of 4 signals favor Codex, route to Claude (medium confidence) to prevent incorrect autonomous execution
- Revision mode never re-classifies existing tasks, preserving manual user overrides

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Modified files (gsd-planner.md, phase-prompt.md) live outside the git repo at ~/.claude/. Both tasks committed as a single git commit tracking the PLAN.md artifact.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Task routing heuristic ready for use by gsd-planner during plan generation
- Phase 3 (worktree parallel execution) can consume executor attributes from PLAN.md
- Backward compatibility ensures existing plans without executor attributes still work

---
*Phase: 02-task-splitting-routing*
*Completed: 2026-03-02*
