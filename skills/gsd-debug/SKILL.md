---
name: gsd-debug
description: Pull real error logs and telemetry from configured observability endpoints for data-driven debugging
argument-hint: "[endpoint-name] [--health]"
allowed-tools: Read, Bash, Grep
---

# /gsd:debug — Live Telemetry Debugging

Pull real error logs from configured endpoints instead of relying on user-pasted logs. This gives agents direct access to live telemetry data for data-driven debugging.

## Step 1: Check Observability Config

Read `.planning/config.json` and check the `observability` section.

```bash
OBS_ENABLED=$(node -e "
  const c = JSON.parse(require('fs').readFileSync('.planning/config.json','utf8'));
  console.log((c.observability && c.observability.enabled) ? 'true' : 'false');
" 2>/dev/null || echo "false")
```

**If not configured or disabled:** Tell the user:

> Observability not configured. Add an `observability` section to `.planning/config.json` to enable.
> See `bin/query-telemetry.sh` header for config format and supported endpoint types (docker, http, file, journalctl).

Then **stop** -- no further action needed.

## Step 2: Query Endpoints

Run `query-telemetry.sh` to pull live data from all configured endpoints (or a specific one if the user named it).

**All endpoints:**

```bash
RESULT=$(bash bin/query-telemetry.sh 2>/tmp/gsd-debug-stderr.txt)
STDERR=$(cat /tmp/gsd-debug-stderr.txt)
```

**Specific endpoint:**

```bash
RESULT=$(bash bin/query-telemetry.sh --endpoint NAME 2>/tmp/gsd-debug-stderr.txt)
STDERR=$(cat /tmp/gsd-debug-stderr.txt)
```

Capture both stdout (structured JSON) and stderr (human-readable summary).

## Step 3: Present Findings

Parse the JSON result. For each endpoint in `results`:

- **Endpoint name** and **type**
- **Number of lines** returned
- **Recent errors/warnings** -- show the most recent 5-10 lines
- **Endpoint errors** (unreachable, timed out) -- note the connectivity issue

Format as a structured summary:

```
## Telemetry Results

### app-logs (docker) -- 12 lines
- 3 ERROR lines in last hour
- Most recent: "2026-03-11 19:00:12 ERROR Connection refused to postgres:5432"
- Pattern: database connectivity issues (3 occurrences)

### error-tracker (http) -- 5 issues
- 2 unresolved in last 24h
- Top issue: "NullPointerException in UserService.getProfile"
```

For endpoints with errors (unreachable), note:

```
### system-logs (file) -- UNREACHABLE
- Error: File not found at /var/log/app/error.log
- Action: Verify the log path in .planning/config.json
```

## Step 4: Suggest Next Steps

Based on findings, suggest concrete debugging actions:

- "3 ERROR lines in app-logs in last hour -- check container restart with `docker ps` and `docker logs`"
- "Sentry shows 5 unresolved issues -- prioritize the NullPointerException (most frequent)"
- "No errors found in any endpoint -- system appears healthy"
- "2 endpoints unreachable -- fix config before debugging"

## Health Check Mode

If the user runs `/gsd:debug --health`, run the health check to verify endpoint connectivity without pulling full logs:

```bash
bash bin/query-telemetry.sh --health
```

This tests each endpoint's reachability and reports status. Use this for first-run validation or when endpoints seem broken.

## When This Skill is Useful

- Debugging a failing deployment or container crash
- Investigating error spikes after a code change
- Validating that a fix resolved an issue (before/after comparison)
- First-time setup verification (--health mode)
