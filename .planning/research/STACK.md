# Stack Research: Version Pinning, Compatibility & Update Wrapping

**Date:** 2026-03-05
**Scope:** What stack additions/changes are needed for v1.2 Upstream Sync
**Constraint:** Zero new external dependencies

---

## 1. Current Stack Inventory

| Component | Role | Key Fact |
|-----------|------|----------|
| `install.sh` | Entrypoint, copies skills/rules/configs, installs GSD via npx | ~468 LOC, bash, uses `set -euo pipefail` |
| `bin/*.sh` | Worktree, codex-task, demo scripts | All bash, structured JSON output |
| `python3 -c` | Inline JSON parsing in bin/ scripts and tests | One-liners only (`import sys,json`), NOT a dependency |
| `node` | Required dep (pre-flight checked), runs `npx get-shit-done-cc` | Already validated by install.sh |
| `~/.claude/get-shit-done/VERSION` | Upstream GSD version file | Single-line semver string (e.g., `1.22.4`) |
| `gsd-tools.cjs` | Upstream GSD CLI tool | Node.js, handles state, phases, validation |
| GSD `update.md` workflow | Upstream update mechanism | Reads VERSION file, calls `npx get-shit-done-cc@latest`, handles changelog |

**Notable pattern:** The codebase already uses `python3 -c "import sys,json; ..."` extensively (40+ call sites in bin/ and test/ scripts) for JSON parsing. This is a de facto stack member, not an external dependency -- Python 3 ships with macOS and every Linux distro the project targets.

---

## 2. Semver Comparison in Bash

### Recommendation: Pure bash, no external tools

Semver comparison needs to handle only `MAJOR.MINOR.PATCH` format (the format used by `~/.claude/get-shit-done/VERSION`). No pre-release tags, no build metadata.

**Implementation pattern:**

```bash
# Split version into components and compare numerically
semver_compare() {
  local v1="$1" v2="$2"
  local IFS='.'
  read -r v1_major v1_minor v1_patch <<< "$v1"
  read -r v2_major v2_minor v2_patch <<< "$v2"

  for pair in "$v1_major:$v2_major" "$v1_minor:$v2_minor" "$v1_patch:$v2_patch"; do
    local a="${pair%%:*}" b="${pair##*:}"
    if (( a > b )); then echo "gt"; return; fi
    if (( a < b )); then echo "lt"; return; fi
  done
  echo "eq"
}

# Range check: is $version within [$min, $max]?
semver_in_range() {
  local version="$1" min="$2" max="$3"
  local cmp_min cmp_max
  cmp_min="$(semver_compare "$version" "$min")"
  cmp_max="$(semver_compare "$version" "$max")"
  [[ "$cmp_min" != "lt" && "$cmp_max" != "gt" ]]
}
```

**Why pure bash:**
- The VERSION file is always `MAJOR.MINOR.PATCH` -- no edge cases requiring a full semver parser.
- `sort -V` exists on macOS and Linux but has subtle portability issues (GNU vs BSD coreutils). Pure arithmetic comparison is safer.
- Adding `semver` npm packages or Python semver libs would violate the zero-dependency constraint.

**Why NOT `sort -V`:** BSD `sort` on macOS does not support `-V` in older versions. The pre-flight already validates bash, so pure bash arithmetic is the safest path.

**Why NOT node/python for this:** The comparison is 15 lines of bash. Shelling out to node or python3 for two integer comparisons per field adds latency and complexity for zero benefit.

---

## 3. Reading/Writing the Compatibility Manifest (`gsd-compat.json`)

### File location: `gsd-compat.json` at repo root

This is a static file shipped with gsd-multi-model, not generated at runtime.

### Recommended format

```json
{
  "addon_version": "1.2.0",
  "gsd_compat": {
    "min": "1.20.0",
    "max": "1.99.99",
    "tested": "1.22.4"
  },
  "node_min": "18"
}
```

**Field rationale:**
- `addon_version` -- tracks gsd-multi-model's own version for diagnostics and future update-checking.
- `gsd_compat.min` -- earliest GSD version where the files/commands this addon depends on exist.
- `gsd_compat.max` -- upper bound before known breaking changes. Use `X.99.99` as "no known ceiling."
- `gsd_compat.tested` -- the exact GSD version the addon was validated against. Informational only.
- `node_min` -- minimum Node.js major version. Currently presence-only, this adds a floor.

### Reading JSON without jq

The codebase already uses `python3 -c` for JSON parsing in 40+ places. Consistency demands the same pattern here:

```bash
read_compat_field() {
  local file="$1" field="$2"
  python3 -c "
import json, sys
d = json.load(open('$file'))
keys = '$field'.split('.')
for k in keys:
    d = d[k]
print(d)
" 2>/dev/null
}

# Usage:
GSD_MIN="$(read_compat_field gsd-compat.json gsd_compat.min)"
GSD_MAX="$(read_compat_field gsd-compat.json gsd_compat.max)"
```

**Why NOT `grep`/`sed`/`awk` for JSON:** Fragile. A nested key like `gsd_compat.min` requires a real parser. The existing codebase already solved this problem with `python3 -c`.

**Why NOT `jq`:** Not installed by default on macOS. Adding a pre-flight check for `jq` or bundling it violates the zero-dependency constraint. `python3` is already validated as a de facto dependency.

**Why NOT `node -e`:** Would work (node is a required dep), but the existing pattern is `python3 -c` everywhere. Mixing two JSON-parsing approaches in the same codebase creates confusion.

### Writing JSON

The compatibility manifest is a static file committed to the repo. It is never written at runtime by the addon scripts. It is hand-edited (or edited by Claude during development) when the tested GSD version range changes. No write tooling needed.

---

## 4. Integration with Existing `install.sh`

### Where compatibility checking fits

The check belongs **after pre-flight (step 1) and before file installation (step 2)**. This is the natural gate: dependencies are verified, but no files have been copied yet.

```
Current install.sh flow:
  1. Pre-flight checks (git, node, claude, codex)
  2. Install skills           <-- TOO LATE to warn
  3. Install rules
  4. Install global configs
  5. Install GSD
  6. Verify integrity
  7. Summary

Proposed flow:
  1. Pre-flight checks (git, node, claude, codex)
  1b. GSD compatibility check  <-- NEW: read VERSION, compare to gsd-compat.json
  2. Install skills
  ...rest unchanged...
```

**Behavior on compatibility failure:**
- **GSD not installed:** Warn but continue. GSD gets installed in step 5. Re-check after step 5.
- **GSD version below min:** `warn()` with message, suggest `npx get-shit-done-cc@latest --global`. Continue (non-blocking -- user may be about to update).
- **GSD version above max:** `warn()` with message explaining the addon has not been tested with this version. Continue (forward-compat is likely fine; the user should not be blocked).
- **GSD version in range:** `ok()` with version displayed.

**Why warn, not hard-fail:** The addon overlay pattern means GSD files and addon files are separate. An out-of-range GSD version may still work. Hard-failing would block users who are one patch version ahead of the tested range. The decision in STATE.md confirms this: "Auto-detect + warn (not auto-repair) -- user stays in control."

---

## 5. Update Wrapper Script

### Recommended approach: `bin/gsd-update.sh`

A new shell script that chains three operations:

1. **Update GSD** -- call the upstream mechanism (`npx get-shit-done-cc@latest --global`)
2. **Reinstall addon** -- re-run `install.sh` (already idempotent)
3. **Verify compatibility** -- read the new VERSION, compare to `gsd-compat.json`, report

### Why a dedicated script instead of extending `install.sh`

- `install.sh` is the addon installer. Adding GSD update logic conflates two responsibilities.
- The update wrapper is a user-facing convenience command. Separating it means `install.sh` stays focused and testable.
- The wrapper can call `install.sh` internally, getting idempotency for free.

### Interaction with upstream GSD update workflow

The upstream GSD update (`/gsd:update`) is a Claude Code skill/workflow -- it runs interactively inside a Claude session with user confirmation, changelog display, etc. `bin/gsd-update.sh` is a non-interactive shell script for CI or quick terminal use. They serve different contexts and should coexist:

- `/gsd:update` -- interactive, shows changelog, asks confirmation
- `bin/gsd-update.sh` -- non-interactive, chains update + reinstall + verify

The wrapper should NOT replicate the upstream changelog/confirmation UX. It should call `npx` directly for the actual update and add only the addon-specific post-steps.

---

## 6. What NOT to Add

| Rejected Addition | Why |
|-------------------|-----|
| **`jq` dependency** | Not on macOS by default. python3 already handles JSON everywhere in this codebase. |
| **`semver` npm package** | Overkill for `MAJOR.MINOR.PATCH` comparison. 15 lines of bash suffice. |
| **Runtime version checks** (on every script run) | STATE.md decision: "Install-time checks only, not runtime." Adds latency to every `bin/` invocation for near-zero benefit. |
| **Auto-repair / auto-update** | STATE.md decision: "Auto-detect + warn, not auto-repair." User stays in control. |
| **Lock file / hash pinning** | GSD is installed via npx (npm manages integrity). Addon files are verified by `install.sh` integrity check. Adding a separate lock file duplicates existing mechanisms. |
| **`package.json` for the addon** | This is not an npm package. It is a git-cloned overlay installed via `bash install.sh`. Adding package.json implies npm semantics that do not apply. |
| **Config file for update preferences** | Premature. Three requirements, one script. No user-configurable knobs needed yet. |
| **node-based version comparison** | Would require either bundling a .cjs file or calling `node -e`. The existing codebase pattern is bash for orchestration, python3 for JSON. Adding a third pattern (node for version comparison) fragments the stack. |

---

## 7. File Inventory for v1.2

| File | Type | Purpose |
|------|------|---------|
| `gsd-compat.json` | New (static) | Compatibility manifest: addon version, GSD version range, tested version |
| `bin/gsd-update.sh` | New (script) | Update wrapper: GSD update + addon reinstall + compat verify |
| `install.sh` | Modified | Add compat check between pre-flight and file installation |
| `test-gsd-update.sh` | New (test) | Integration tests for update wrapper |

**No new dependencies. No new languages. No new runtime tools.**

---

## 8. Summary of Prescriptive Decisions

1. **Semver comparison:** Pure bash arithmetic on split `MAJOR.MINOR.PATCH`. No `sort -V`, no npm semver, no python.
2. **JSON reading:** `python3 -c "import json"` one-liners, matching the 40+ existing call sites.
3. **JSON writing:** Not needed. `gsd-compat.json` is a static committed file.
4. **Compat check placement:** After pre-flight, before file install. Warn-only, never hard-fail.
5. **Update wrapper:** Separate `bin/gsd-update.sh` script. Calls `npx` for GSD, then `install.sh` for addon, then compat verify.
6. **No runtime checks:** Install-time only, per STATE.md decision.

---
*Research completed: 2026-03-05*
