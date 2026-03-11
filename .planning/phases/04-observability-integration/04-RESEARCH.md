# Phase 04: Observability Integration - Research

**Researched:** 2026-03-11
**Domain:** Config-driven telemetry querying for Claude Code executor agents
**Confidence:** HIGH

## Summary

Phase 04 adds an opt-in observability layer that lets executor agents query real telemetry data (logs, errors, metrics) from configured endpoints. The system follows the same config-driven, shell-script-orchestrated pattern established by Phase 02 (gates) and Phase 03 (entropy sweeps). When endpoints are configured in `.planning/config.json`, agents can pull error logs during debugging and query telemetry before/after making changes. When unconfigured, everything is a no-op.

This is a thin integration layer, not a telemetry platform. The project already has a mature pattern for config-driven shell scripts that parse `.planning/config.json` via Node one-liners, produce structured JSON on stdout, and human-readable output on stderr. Phase 04 reuses this exact pattern for telemetry queries.

**Primary recommendation:** Build a `bin/query-telemetry.sh` orchestrator (matching gate-check.sh/entropy-sweep.sh patterns), a `/gsd:debug` skill, and wire executor agents to optionally query telemetry via a lightweight skill injection pattern.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None -- all decisions deferred to Claude's discretion.

### Claude's Discretion
All implementation decisions deferred to Claude's judgment. /gsd:drive auto-generated this context -- no user discussion occurred. Research and planning agents should make reasonable default choices.

### Deferred Ideas (OUT OF SCOPE)
None.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| OBSV-01 | `.planning/config.json` supports observability endpoint config (log sources, error trackers) | Config schema design (see Architecture Patterns) follows existing gates/entropy config conventions |
| OBSV-02 | `/gsd:debug` can pull real error logs from configured endpoints | New skill + shell script that queries configured log endpoints (see Standard Stack, Code Examples) |
| OBSV-03 | Executor agents query telemetry before/after changes when endpoints are configured | Skill injection pattern for execute-phase agents (see Architecture Patterns) |
</phase_requirements>

## Standard Stack

### Core
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| bash + node one-liners | Config parsing, script orchestration | Matches bin/gate-check.sh and bin/entropy-sweep.sh patterns exactly |
| curl | HTTP requests to telemetry endpoints | Available everywhere, no dependencies, timeout support |
| jq-style node -e | JSON response parsing | Project already uses `node -e` for all JSON ops; no jq dependency needed |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| docker logs | Container log retrieval | When endpoint type is "docker" |
| journalctl | Systemd service logs | When endpoint type is "journalctl" |
| tail/grep | Local file log parsing | When endpoint type is "file" |
| curl + auth headers | Authenticated API calls | When endpoint has auth config (API keys, bearer tokens) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Shell scripts | Node.js CLI tool | Node would be cleaner for HTTP but breaks the bin/ convention; shell + curl is consistent |
| Multiple endpoint-specific tools | Single unified query script | Unified script with endpoint-type dispatch keeps the interface clean |
| Direct API integration (Sentry SDK, etc.) | curl to REST APIs | curl is zero-dependency and works with any API that has HTTP endpoints |

## Architecture Patterns

### Config Schema for Observability

Extends `.planning/config.json` with a new `observability` top-level key, following the same pattern as `gates` and `entropy`:

```json
{
  "observability": {
    "enabled": true,
    "endpoints": {
      "app-logs": {
        "type": "docker",
        "container": "my-app",
        "lines": 100,
        "filter": "ERROR|WARN"
      },
      "error-tracker": {
        "type": "http",
        "url": "https://sentry.io/api/0/projects/org/proj/issues/",
        "headers": {
          "Authorization": "Bearer ${SENTRY_AUTH_TOKEN}"
        },
        "response_path": ".[0:5]",
        "timeout_seconds": 10
      },
      "system-logs": {
        "type": "file",
        "path": "/var/log/app/error.log",
        "lines": 50,
        "filter": "ERROR"
      },
      "service-logs": {
        "type": "journalctl",
        "unit": "my-service",
        "lines": 50,
        "since": "1h"
      }
    }
  }
}
```

**Key design decisions:**
- `enabled: true/false` at top level for global kill switch (matches gates/entropy)
- Named endpoints (not an array) so users can reference specific sources
- `type` field drives dispatch: "docker", "http", "file", "journalctl"
- Environment variable substitution in strings via `${VAR_NAME}` pattern (secrets stay out of config)
- Each endpoint has type-specific fields plus common ones (`timeout_seconds`, `filter`)

### Endpoint Type Dispatch

```
query-telemetry.sh
  |-- type: docker    -> docker logs --tail N [--since T] container | grep filter
  |-- type: http      -> curl -s -H headers url | node -e "parse response_path"
  |-- type: file      -> tail -n N path | grep filter
  |-- type: journalctl -> journalctl -u unit -n N --since T --no-pager | grep filter
```

### Recommended Project Structure

```
bin/
  query-telemetry.sh       # Telemetry query orchestrator (new)
  test-query-telemetry.sh  # Tests for query-telemetry (new)
skills/
  gsd-debug/
    SKILL.md               # /gsd:debug entry point (new)
  observe/
    SKILL.md               # Executor telemetry injection skill (new)
```

### Pattern: Config-Driven Script (established in Phase 02/03)

**What:** Shell script reads `.planning/config.json` via node -e, dispatches to sub-checks, produces JSON on stdout and human-readable on stderr.

**Example from entropy-sweep.sh (to replicate):**
```bash
# Load config
CONFIG_FILE="$PROJECT_ROOT/.planning/config.json"
if [ -f "$CONFIG_FILE" ]; then
  OBS_JSON=$(node -e "
    const c = JSON.parse(require('fs').readFileSync('$CONFIG_FILE','utf8'));
    const o = c.observability || {};
    console.log(JSON.stringify({
      enabled: o.enabled !== undefined ? o.enabled : false,
      endpoints: o.endpoints || {}
    }));
  " 2>/dev/null || echo '{}')
fi
```

### Pattern: Environment Variable Substitution

For HTTP endpoints with auth tokens, config stores `${SENTRY_AUTH_TOKEN}` and the script substitutes at runtime:

```bash
resolve_env_vars() {
  local input="$1"
  echo "$input" | sed 's/\${/\n${/g' | while IFS= read -r line; do
    if [[ "$line" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; then
      local var_name="${BASH_REMATCH[1]}"
      local var_value="${!var_name:-}"
      echo "${line/\$\{$var_name\}/$var_value}"
    else
      echo "$line"
    fi
  done | tr -d '\n'
}
```

### Pattern: Skill Injection for Executor Agents

OBSV-03 requires executors to query telemetry before/after changes. This uses the same skill-based protocol injection as gate-check (Phase 02):

A lightweight `skills/observe/SKILL.md` that executors load during execute phase:
- Before starting a task: query relevant endpoints, include findings in context
- After task completion: re-query to confirm issue resolution
- No-op when observability is disabled or no endpoints configured

### Anti-Patterns to Avoid
- **Building a full monitoring dashboard:** This is a query tool, not a visualization layer. Output is text for agent consumption.
- **Storing credentials in config.json:** Always use `${ENV_VAR}` references. Never store actual tokens.
- **Making observability a hard requirement:** Everything must be opt-in. Unconfigured = no-op, never an error.
- **Parsing complex log formats:** The script greps for patterns. Deep log parsing is out of scope.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP requests | Custom Node HTTP client | `curl` with proper flags | Zero deps, timeout support, header injection, widely understood |
| JSON path extraction | Custom JSON walker | `node -e` with bracket notation | Already used everywhere in the project |
| Log retrieval | Custom log aggregator | `docker logs`, `journalctl`, `tail` | OS-native tools do this perfectly |
| Config schema validation | Custom JSON schema validator | Simple `node -e` existence checks | Schema is small enough; formal validation is overkill |
| Auth token management | Token refresh / OAuth flow | `${ENV_VAR}` substitution | Users manage their own tokens; we just reference them |

**Key insight:** This phase is a thin shell around existing CLI tools (curl, docker, journalctl, tail). The value is in the unified config format and structured output, not in reimplementing log retrieval.

## Common Pitfalls

### Pitfall 1: Secrets in Config Files
**What goes wrong:** User puts actual API keys in `.planning/config.json`, which gets committed to git.
**Why it happens:** Convenience over security.
**How to avoid:** Use `${ENV_VAR}` substitution pattern. Document it clearly. Consider warning if config contains string values that look like tokens (long alphanumeric strings).
**Warning signs:** Config file containing long base64-like strings.

### Pitfall 2: Blocking on Unreachable Endpoints
**What goes wrong:** HTTP endpoint is down, curl hangs, entire execute flow stalls.
**Why it happens:** No timeout configured or timeout too long.
**How to avoid:** Default timeout of 10 seconds. `curl --max-time 10`. On timeout, return empty results with a warning, never block.
**Warning signs:** Script hanging during execution.

### Pitfall 3: Noisy Telemetry Overwhelming Agent Context
**What goes wrong:** Query returns 1000 log lines, agents get confused by volume.
**Why it happens:** No limits on response size.
**How to avoid:** Default `lines: 50` cap. Truncate HTTP responses to first N KB. Always summarize, never dump raw.
**Warning signs:** Agent responses becoming incoherent after telemetry injection.

### Pitfall 4: Making Observability Required for Workflow
**What goes wrong:** Users without telemetry endpoints get errors or blocked workflows.
**Why it happens:** Missing no-op path when observability is unconfigured.
**How to avoid:** Default `enabled: false` (or treat missing config as disabled). Every code path checks config first.
**Warning signs:** Error messages about missing observability config.

### Pitfall 5: Docker Socket Permissions
**What goes wrong:** `docker logs` fails because the user doesn't have docker group membership.
**Why it happens:** Docker requires socket access.
**How to avoid:** Catch docker command failures gracefully, report as "endpoint unreachable" not a hard error.
**Warning signs:** Permission denied errors in test output.

## Code Examples

### query-telemetry.sh Skeleton (follows entropy-sweep.sh pattern)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bin/query-telemetry.sh                          # query all endpoints
#   bin/query-telemetry.sh --endpoint app-logs      # query single endpoint
#   bin/query-telemetry.sh --json-only              # suppress stderr

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load config (same pattern as entropy-sweep.sh)
CONFIG_FILE="$PROJECT_ROOT/.planning/config.json"
# ... parse observability section ...

# Dispatch by endpoint type
query_docker() {
  local container="$1" lines="${2:-100}" filter="${3:-}"
  local output
  output=$(docker logs --tail "$lines" "$container" 2>&1) || { echo "[]"; return; }
  if [ -n "$filter" ]; then
    output=$(echo "$output" | grep -E "$filter" || true)
  fi
  # Convert to JSON array of log lines
  node -e "
    const lines = process.argv[1].split('\n').filter(Boolean);
    console.log(JSON.stringify(lines));
  " "$output"
}

query_http() {
  local url="$1" timeout="${2:-10}"
  # headers passed via temp file or args
  curl -s --max-time "$timeout" -H "..." "$url" || echo '{"error":"request failed"}'
}

# ... similar for file, journalctl ...

# Output: JSON on stdout, human summary on stderr
```

### /gsd:debug Skill Pattern

```markdown
---
name: gsd-debug
description: Pull real error logs and telemetry from configured endpoints for debugging
argument-hint: "[endpoint-name] [--last N]"
allowed-tools: Read, Bash
---

# /gsd:debug

## Step 1: Load observability config
Read .planning/config.json, check observability.enabled

## Step 2: Query endpoints
Run: bash bin/query-telemetry.sh [--endpoint NAME]

## Step 3: Present findings
Format results as structured context for the agent
```

### Executor Telemetry Injection (OBSV-03)

```markdown
# skills/observe/SKILL.md
# Loaded by executors during execute phase

## Before Task
If observability.enabled:
  results = bash bin/query-telemetry.sh --json-only
  Include error counts and recent errors in task context

## After Task
If observability.enabled:
  results = bash bin/query-telemetry.sh --json-only
  Compare before/after: "Errors reduced from N to M" or "New errors detected"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Agents read only source code | Agents can query live telemetry | Phase 04 | Debugging is data-driven, not guess-based |
| User pastes error logs manually | `/gsd:debug` pulls logs automatically | Phase 04 | Removes human bottleneck in debug loop |
| No structured telemetry config | Config-driven endpoint definitions | Phase 04 | One-time setup, reusable across sessions |

## Open Questions

1. **Response size limits for HTTP endpoints**
   - What we know: Need to cap response size to avoid overwhelming agent context
   - What's unclear: Optimal cap (1KB? 5KB? configurable?)
   - Recommendation: Default to 5KB / 50 lines, make configurable per endpoint via `max_lines` or `max_bytes`

2. **Before/after telemetry for OBSV-03 -- timing**
   - What we know: Executors should query before starting and after completing a task
   - What's unclear: How to detect "task boundary" in the executor flow
   - Recommendation: The observe skill documents when to call it; executor agents invoke explicitly at task start/end (not automated hooks)

3. **Endpoint health checking**
   - What we know: Endpoints may be unreachable
   - What's unclear: Should there be a `bin/query-telemetry.sh --health` mode?
   - Recommendation: Yes, simple connectivity check per endpoint. Useful for `/gsd:debug` first-run validation.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash test scripts (matching project convention) |
| Config file | none -- tests are self-contained bash scripts |
| Quick run command | `bash bin/test-query-telemetry.sh` |
| Full suite command | `bash bin/test-query-telemetry.sh && bash bin/test-install.sh` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| OBSV-01 | Config schema parsed correctly, missing config = no-op | unit | `bash bin/test-query-telemetry.sh` | No -- Wave 0 |
| OBSV-02 | /gsd:debug invokes query-telemetry, formats output | integration | `bash bin/test-query-telemetry.sh` | No -- Wave 0 |
| OBSV-03 | Executor observe skill queries before/after, handles disabled | unit | `bash bin/test-query-telemetry.sh` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `bash bin/test-query-telemetry.sh`
- **Per wave merge:** `bash bin/test-query-telemetry.sh && bash bin/test-install.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `bin/test-query-telemetry.sh` -- covers OBSV-01, OBSV-02, OBSV-03
- [ ] Test fixtures for each endpoint type (mock docker, mock HTTP, temp log files)
- [ ] `test-install.sh` updates to verify new files exist

## Sources

### Primary (HIGH confidence)
- Project source: `bin/gate-check.sh`, `bin/entropy-sweep.sh` -- established config-driven script pattern
- Project source: `bin/gsd-tools-gate.cjs` -- established CLI wrapper pattern
- Project source: `skills/gate-check/SKILL.md` -- established skill injection pattern
- Project source: `.planning/config.json` -- existing schema to extend

### Secondary (MEDIUM confidence)
- curl documentation -- timeout flags, header injection, error handling
- docker logs documentation -- --tail, --since flags

### Tertiary (LOW confidence)
- None -- this phase is primarily about applying established project patterns to a new domain

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- reuses exact patterns from Phase 02/03 (shell scripts, node -e, config.json)
- Architecture: HIGH -- config schema and script structure directly mirror entropy-sweep.sh
- Pitfalls: HIGH -- common issues with HTTP timeouts, secrets, and Docker permissions are well-known
- Endpoint types: MEDIUM -- the 4 types (docker, http, file, journalctl) cover most use cases but users may need others

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable domain, project-internal patterns)
