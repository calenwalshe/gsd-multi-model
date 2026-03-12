---
name: gsd-multi:observe
description: Executor telemetry injection protocol for before/after task comparison during execute phase
argument-hint: ""
allowed-tools: Read, Bash
---

# Observe -- Executor Telemetry Protocol

This skill documents a protocol for executor agents to capture telemetry snapshots before and after task changes. It is **not** an automated hook -- executors invoke these steps manually at task boundaries.

## Purpose

During execute phase, code changes may introduce or resolve runtime errors. By querying telemetry before starting a task and again after completing it, executors can detect regressions early and confirm fixes empirically.

## Before Task

**At the start of each task**, check if observability is configured and capture a baseline snapshot.

```bash
OBS_ENABLED=$(node -e "
  const c = JSON.parse(require('fs').readFileSync('.planning/config.json','utf8'));
  console.log((c.observability && c.observability.enabled) ? 'true' : 'false');
" 2>/dev/null || echo "false")
```

**If enabled:** Query all endpoints and store the result:

```bash
BEFORE_SNAPSHOT=$(bash bin/query-telemetry.sh --json-only 2>/dev/null)
```

Summarize the current state:

> Current state: N errors in endpoint-A, M warnings in endpoint-B

**If not configured or disabled:**

> Observability not configured -- skipping telemetry snapshot.

Proceed with the task normally. This is a no-op, not an error.

## After Task

**After completing a task** (before committing), if observability was active in the "Before" step, query again and compare:

```bash
AFTER_SNAPSHOT=$(bash bin/query-telemetry.sh --json-only 2>/dev/null)
```

Compare before/after results:

- **Errors reduced:** "Errors reduced from N to M in endpoint-A" -- good sign, fix is working
- **New errors detected:** "New errors detected in endpoint-B: [first 3 lines]" -- possible regression, investigate before committing
- **No change:** "Telemetry unchanged after task" -- neutral, expected for non-runtime changes

Include the comparison in the task commit notes if relevant findings exist.

## When to Skip

Skip telemetry queries when the task involves only:

- Documentation changes (markdown, comments)
- Configuration file updates (planning files, config.json)
- Planning artifacts (STATE.md, SUMMARY.md, ROADMAP.md)
- Test-only changes that do not affect runtime behavior

**Only query for code changes that could affect runtime behavior** -- source files, scripts, deployment configs, database migrations.

## Important Notes

- This skill documents a **manual protocol**, not an automated hook
- Executors decide when to invoke these steps based on task type
- All telemetry queries are best-effort -- failures are warnings, never blockers
- Do not let telemetry results block task completion unless new errors are clearly caused by the current change
- When in doubt, note the telemetry findings in the commit message and continue
