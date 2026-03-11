---
name: gate-check
description: Deterministic quality gates that run before every task commit during execute phase — blocks commits when lint, architecture, or structural checks fail
argument-hint: ""
allowed-tools: Read, Bash, Grep
---

# Gate Check — Pre-Commit Quality Gates

Deterministic gates that intercept the task commit flow during execute phase. Gates run **after staging** and **before committing**. If any gate fails, the commit is blocked until violations are fixed.

## Why Gates Exist

Without gates, executor agents commit freely and quality issues surface late (during verify-work or worse, in production). Gates catch violations at the earliest possible point: before the commit happens.

## Gate Types

| Gate | What It Checks | When Active |
|------|---------------|-------------|
| **Lint** | Runs project linter on staged files | When linter detected or configured |
| **Architecture** | Validates module boundaries per `.architecture.json` | When `.architecture.json` exists |
| **Structural** | Checks plan-defined assertions (file-exists, file-contains, etc.) | When `--plan-path` provided and plan has `<structural_tests>` |

## Modified Task Commit Protocol

**Replace the standard task_commit protocol with this gate-augmented version:**

### 1. Check modified files

```bash
git status --short
```

### 2. Stage files individually (NEVER `git add .` or `git add -A`)

```bash
git add src/api/auth.ts
git add src/types/user.ts
```

### 3. Run gates on staged files

```bash
GATE_RESULT=$(bash bin/gate-check.sh 2>/dev/null)
GATE_EXIT=$?
```

Or with the CLI wrapper (equivalent):

```bash
GATE_RESULT=$(node bin/gsd-tools-gate.cjs run --raw 2>/dev/null)
GATE_EXIT=$?
```

For structural tests, pass the current plan path:

```bash
GATE_RESULT=$(bash bin/gate-check.sh --plan-path ".planning/phases/02-foo/02-01-PLAN.md" 2>/dev/null)
GATE_EXIT=$?
```

### 4. Handle gate result

**If gates PASS** (`GATE_EXIT` is 0): proceed to commit.

**If gates FAIL** (`GATE_EXIT` is 1):
1. Read the failure output (stderr has human-readable details)
2. Fix each violation:
   - **Lint failures**: Fix the code issues reported by the linter
   - **Architecture violations**: Remove disallowed imports/references between modules
   - **Structural failures**: Create missing files, add required content
3. Re-stage the fixed files
4. Re-run gates
5. Only proceed to commit when gates pass

### 5. Commit

```bash
git commit -m "{type}({phase}-{plan}): {concise task description}

- {key change 1}
- {key change 2}
"
```

### 6. Record hash

```bash
TASK_COMMIT=$(git rev-parse --short HEAD)
```

## Gate Output Format

Gates produce structured JSON on stdout:

```json
{
  "passed": false,
  "duration_ms": 342,
  "gates": [
    {"name": "lint", "passed": true, "files_checked": 3, "message": "All files pass lint"},
    {"name": "architecture", "passed": false, "violations": [
      {"file": "skills/foo/SKILL.md", "rule": "no-circular-skill-deps", "message": "...", "fix": "..."}
    ]}
  ]
}
```

Human-readable summary goes to stderr with color-coded PASS/FAIL indicators.

## Gate Configuration

Gates are configured in `.planning/config.json` under the `gates` key:

```json
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": true, "command": "", "auto_detect": true },
    "architecture": { "enabled": true, "config_path": ".architecture.json" },
    "structural": { "enabled": true },
    "timeout_seconds": 10,
    "on_timeout": "warn"
  }
}
```

## Emergency Escape

If gates are blocking progress due to a false positive or environment issue:

1. Set `gates.enabled` to `false` in `.planning/config.json`
2. Commit your changes
3. Re-enable gates immediately after
4. Document the skip in SUMMARY.md under "Deviations from Plan"

**Do not leave gates disabled.** The escape is for emergencies only.

## CLI Reference

```bash
# Run all gates on staged files
node bin/gsd-tools-gate.cjs run

# Run gates with structural tests from a plan
node bin/gsd-tools-gate.cjs run --plan-path <path>

# Run architecture check on specific files
node bin/gsd-tools-gate.cjs check-architecture --files file1.js file2.sh

# Show gate configuration status
node bin/gsd-tools-gate.cjs status
```

## Scope

Gates only check **source files** -- `.planning/` files are excluded automatically. Planning doc commits (via `gsd-tools.cjs commit`) do not trigger gates.
