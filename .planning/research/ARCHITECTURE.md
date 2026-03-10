# Architecture: Version Compatibility & Update Orchestration

**Research for:** v1.2 Upstream Sync milestone
**Date:** 2026-03-05

## Context

gsd-multi-model is an addon that installs alongside the base GSD framework (`get-shit-done-cc`). The base framework updates via `npx get-shit-done-cc@latest`, which performs a **wipe-and-replace** of three directory trees under `~/.claude/`:

| Wiped on update | Contents |
|-----------------|----------|
| `commands/gsd/` | Slash-command definitions (33 `.md` files) |
| `get-shit-done/` | Core runtime: `VERSION`, `bin/`, `templates/`, `workflows/`, `references/` |
| `agents/gsd-*` | Agent prompt files (planner, executor, verifier, debugger, etc.) |

The addon's installed artifacts live in locations the base installer **does not touch**:

| Addon artifact | Install location | Touched by GSD update? |
|----------------|------------------|------------------------|
| Skills | `~/.claude/skills/{init-gsd,codex-review,gsd-codex-verify}/` | No |
| Rules | `~/.claude/rules/*.md` | No |
| Global Claude config | `~/.claude/CLAUDE.md` | No (explicitly preserved) |
| Global Codex config | `~/.codex/AGENTS.md`, `~/.codex/config.toml` | No |
| Bin scripts | Repo-local `bin/` (not installed globally) | No |

**Key insight:** The addon survives GSD updates structurally, but may break functionally if the base changes APIs, template schemas, or agent prompt interfaces that the addon depends on.

## What Needs Protection

The addon has **implicit dependencies** on GSD internals:

1. **Agent prompt structure** -- The `/init-gsd` skill references `gsd-planner.md` behavior. If the planner prompt changes its output format, the addon's task-splitting heuristic could break.
2. **PLAN.md XML schema** -- The addon extended the schema with `executor` and `confidence` attributes (v1.0, Dimension 9). If GSD changes the XML schema, parsing in `codex-task.sh` breaks.
3. **Command interface** -- The addon assumes `/gsd:new-project`, `/gsd:execute-phase`, `/gsd:verify-work` exist and behave as documented. GSD could rename or restructure these.
4. **VERSION file contract** -- The addon reads `~/.claude/get-shit-done/VERSION` to detect the installed GSD version. This is a stable interface (used by GSD's own update workflow).

## Component Design

### New File: `gsd-compat.json` (repo root)

```json
{
  "addon_version": "1.2.0",
  "gsd_compat": {
    "min": "1.20.0",
    "max": "1.99.99",
    "tested": "1.22.4"
  },
  "checked_interfaces": [
    "VERSION file at ~/.claude/get-shit-done/VERSION",
    "commands/gsd/ directory structure",
    "agents/gsd-planner.md executor routing",
    "PLAN.md XML task schema with executor attribute"
  ]
}
```

**Location:** `<repo>/gsd-compat.json` (shipped in the gsd-multi-model repo, read at install time). Not installed to `~/.claude/` -- stays in the repo as the source of truth for what GSD versions this addon is tested against.

**Rationale:** JSON for machine-readability. The `checked_interfaces` field is documentation only (for humans), not parsed programmatically.

### New File: `bin/gsd-update.sh` (update wrapper)

A single-command orchestrator that chains three operations:

1. Update GSD base via `npx get-shit-done-cc@latest --global`
2. Re-run addon installer via `bash install.sh`
3. Verify compatibility of the new GSD version against `gsd-compat.json`

**Location:** `<repo>/bin/gsd-update.sh` -- invoked from the repo checkout directory.

### Modified File: `install.sh` (compat check added)

The existing installer gains a new step between preflight checks (step 0) and skill installation (step 1). This step:

1. Reads `~/.claude/get-shit-done/VERSION`
2. Reads `gsd-compat.json` from `$SCRIPT_DIR`
3. Compares the installed GSD version against `min`/`max` range
4. Emits a warning (not a hard fail) if outside range
5. Records the detected GSD version for the summary banner

No existing steps are removed or reordered. The new check is additive.

## Data Flow

```
                         gsd-compat.json
                        (repo, static)
                              |
                              v
 install.sh -----> read_gsd_version() -----> ~/.claude/get-shit-done/VERSION
     |                    |
     |                    v
     |            compare_semver(installed, min, max)
     |                    |
     |             warn if outside range
     |                    |
     v                    v
 [existing install steps continue unchanged]


 gsd-update.sh:
   1. npx get-shit-done-cc@latest --global   --> updates VERSION, commands/, agents/, get-shit-done/
   2. bash install.sh                         --> re-copies skills, rules, configs; runs compat check
   3. bash test-install.sh                    --> verifies all files present and matching
```

## Integration Points with Existing `install.sh`

### Insert point for compat check

After `preflight_check` (line 121) and before skill installation (line 126). The new function `compat_check` is called here. It is a **non-blocking warning** -- the installer continues even if GSD is outside the tested range, because:

- The user may be intentionally running a newer GSD version
- A hard fail would prevent reinstalling addon files (which might still work)
- The warning gives the user actionable information

### Summary banner update

The existing summary (lines 433-462) is extended to show:

```
 GSD base version: 1.22.4 (tested: 1.20.0 - 1.99.99)
```

or, if outside range:

```
 GSD base version: 1.19.0 (WARNING: outside tested range 1.20.0 - 1.99.99)
```

### Counters

The existing `WARNINGS` counter is incremented if GSD is outside range. No new counter needed.

## New vs Modified Components

| Component | Type | File | Notes |
|-----------|------|------|-------|
| `gsd-compat.json` | NEW | `<repo>/gsd-compat.json` | Version range + tested version |
| `bin/gsd-update.sh` | NEW | `<repo>/bin/gsd-update.sh` | Update wrapper script |
| `install.sh` | MODIFIED | `<repo>/install.sh` | Add `compat_check` function + summary line |
| `test-install.sh` | MODIFIED | `<repo>/test-install.sh` | Add compat file presence check |

## Build Order (dependency graph)

```
Phase 1: gsd-compat.json
   No dependencies. Pure data file.
   Must be created first because both install.sh and gsd-update.sh read it.

Phase 2: install.sh compat check
   Depends on: gsd-compat.json (reads it)
   Adds: compat_check() function, summary banner update
   Testable independently: run install.sh, observe warning output

Phase 3: bin/gsd-update.sh
   Depends on: install.sh (calls it), gsd-compat.json (reads it for post-update verify)
   This is the last piece because it orchestrates the other two.

Phase 4: test updates
   Depends on: all above
   Update test-install.sh to verify gsd-compat.json exists
   Add test-gsd-update.sh for the wrapper script
```

**Suggested plan count:** 2-3 plans

- Plan 1: Create `gsd-compat.json` + add `compat_check` to `install.sh` + update `test-install.sh`
- Plan 2: Create `bin/gsd-update.sh` + its test suite
- Plan 3 (optional): Update PROJECT.md, ROADMAP.md, REQUIREMENTS.md specs

## Semver Comparison Strategy

Bash does not have native semver comparison. Two options:

**Option A: Shell-only (preferred, matches project constraint of zero external deps)**

```bash
# Split version into major.minor.patch, compare numerically
ver_to_int() {
  local IFS=.
  local parts=($1)
  echo $(( ${parts[0]} * 10000 + ${parts[1]} * 100 + ${parts[2]} ))
}
```

This handles the `X.Y.Z` format that GSD uses. It fails for versions with 3+ digit minor/patch (e.g., `1.200.3`), but GSD is currently at `1.22.4` and semver conventions make 3-digit components rare enough that this is acceptable. If needed, expand to `* 1000000 / * 1000 / * 1`.

**Option B: Node one-liner (available since node is a required dep)**

```bash
node -e "const s=require('child_process');process.exit(require('semver').gte('$1','$2')?0:1)"
```

Rejected -- requires the `semver` npm package which is not guaranteed to be available.

**Decision:** Option A with the `* 1000000 / * 1000 / * 1` multipliers for safety.

## Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| GSD changes VERSION file location | Low | High | Fallback: check multiple known paths (same approach as GSD's own update workflow) |
| GSD removes wipe-and-replace behavior | Low | Medium | The update wrapper still works; compat check still works; just less critical |
| User runs addon install without GSD | Medium | Low | Already handled: install.sh step 5 installs GSD if missing |
| GSD breaks XML schema the addon parses | Medium | High | The `checked_interfaces` list in gsd-compat.json documents what to re-test when bumping the version range |

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Warning not hard-fail on version mismatch | User autonomy; addon files may still work; prevents install deadlock |
| `gsd-compat.json` in repo root, not `~/.claude/` | Source of truth stays in version control; not an installed runtime artifact |
| Update wrapper is a separate script, not a flag on install.sh | Separation of concerns; install.sh remains idempotent for addon-only reinstalls |
| Shell-only semver comparison | Matches project constraint: no external dependencies beyond git/node/claude/codex |
| 3-phase build order (data, integration, orchestration) | Each phase is independently testable and deliverable |

---
*Research completed: 2026-03-05*
