---
phase: 04-observability-integration
plan: 01
subsystem: infra
tags: [bash, telemetry, config, curl, docker, journalctl, observability]

requires:
  - phase: 02-deterministic-gates
    provides: "Config-driven shell script pattern (gate-check.sh)"
  - phase: 03-entropy-management
    provides: "entropy-sweep.sh pattern to replicate"
provides:
  - "query-telemetry.sh orchestrator with 4 endpoint types"
  - "Observability config schema in .planning/config.json"
  - "Test suite for telemetry query infrastructure"
affects: [04-02, gsd-debug, executor-observe]

tech-stack:
  added: [curl, docker-logs, journalctl, tail]
  patterns: [endpoint-type-dispatch, env-var-substitution, health-check-mode]

key-files:
  created:
    - bin/query-telemetry.sh
    - bin/test-query-telemetry.sh
  modified:
    - .planning/config.json

key-decisions:
  - "Env var substitution via bash regex loop (not sed) for portability"
  - "Health check mode uses lightweight probes (file -f, curl --head, docker inspect)"
  - "Unreachable endpoints produce warnings with empty results, never hard failure"

patterns-established:
  - "Endpoint type dispatch: type field drives handler selection"
  - "resolve_env_vars(): replaces ${VAR} patterns in config strings at runtime"

requirements-completed: [OBSV-01]

duration: 4min
completed: 2026-03-11
---

# Phase 04 Plan 01: Telemetry Query Orchestrator Summary

**Config-driven telemetry query orchestrator with docker/http/file/journalctl dispatch, env var substitution, and health check mode**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-11T19:16:12Z
- **Completed:** 2026-03-11T19:20:13Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Built query-telemetry.sh following exact entropy-sweep.sh/gate-check.sh conventions (JSON stdout, human stderr, exit codes)
- Config schema supports 4 endpoint types (docker, http, file, journalctl) with env var substitution for secrets
- 14 automated tests covering config parsing, file dispatch, HTTP timeout, filtering, health checks, and edge cases
- Unconfigured/disabled observability is a clean no-op (exit 0, empty JSON)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create query-telemetry.sh orchestrator and config schema** - `404dbf7` (feat)
2. **Task 2: Create test-query-telemetry.sh test suite** - `5e0ee61` (test)

## Files Created/Modified
- `bin/query-telemetry.sh` - Telemetry query orchestrator with endpoint-type dispatch (290 lines)
- `bin/test-query-telemetry.sh` - Test suite with 14 tests covering all paths (380 lines)
- `.planning/config.json` - Added observability section (enabled:false, empty endpoints)

## Decisions Made
- Used bash regex loop for env var substitution instead of sed for better portability
- Health check mode uses lightweight probes per type (file existence, curl HEAD, docker inspect, systemctl is-active)
- All endpoint failures produce warnings with empty results, never hard failures (exit 0 always)
- Docker and journalctl tests run when commands available, skip gracefully otherwise

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- query-telemetry.sh ready for /gsd:debug skill (Plan 02)
- Config schema ready for executor observe skill (Plan 02)
- test-install.sh updates needed in Plan 02

---
*Phase: 04-observability-integration*
*Completed: 2026-03-11*
