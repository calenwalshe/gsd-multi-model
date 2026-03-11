# Phase 7: Compatibility Manifest & Install-Time Check - Research

**Researched:** 2026-03-06
**Domain:** Bash semver comparison, JSON manifest design, install.sh integration
**Confidence:** HIGH

## Summary

Phase 7 adds three things to the codebase: (1) a static `gsd-compat.json` manifest declaring the tested GSD version range, (2) a `semver_compare()` function using pure bash integer arithmetic, and (3) a `compat_check()` function in `install.sh` that reads the VERSION file, compares it against the manifest range, and emits a warning or confirmation. The total scope is approximately 60-70 new lines of bash plus a 7-line JSON file.

All implementation details have been verified experimentally. The semver comparison approach has been tested with edge cases including 3-digit components (1.100.0 vs 1.99.99), boundary equality, and range checks. The python3 JSON reading pattern has been confirmed against the exact `gsd-compat.json` schema. The VERSION file format (plain text, no trailing newline, exactly `MAJOR.MINOR.PATCH`) has been confirmed by inspecting the actual file on disk.

**Primary recommendation:** Implement as a single plan (07-01-PLAN.md) with three deliverables: gsd-compat.json, install.sh modifications (semver_compare + compat_check + summary update), and test additions. The scope is small enough that splitting into sub-plans would add overhead without reducing risk.

## Standard Stack

### Core (no new dependencies)

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Bash | 3.2+ (macOS default) | semver_compare(), compat_check() functions | Already the project language; arithmetic comparison on split integers is ~15 lines |
| python3 | 3.x (macOS ships it) | JSON parsing of gsd-compat.json | 40+ existing call sites in bin/ and test/ scripts use `python3 -c "import json"` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Pure bash arithmetic | `sort -V` | Works on recent macOS (verified) but NOT portable to older macOS/BSD; project decided pure bash |
| `python3 -c` for JSON | `jq` | Not installed by default on macOS; violates zero-dependency constraint |
| `python3 -c` for JSON | `node -e` | Would work (node is required dep), but breaks established `python3 -c` pattern used in 40+ places |
| `python3 -c` for JSON | `grep`/`sed` on JSON | Fragile for nested keys like `gsd_compat.min`; real parser is safer |

**Installation:** No packages to install. All tools are already present.

## Verified Implementation Patterns

### Pattern 1: semver_compare() Function

**What:** Pure bash function that compares two `MAJOR.MINOR.PATCH` version strings.
**Returns:** -1 (first < second), 0 (equal), 1 (first > second).
**Verified:** Tested with 10 edge cases including 3-digit components, major/minor/patch boundaries, and range checks. All passed.

```bash
# Verified approach -- all edge cases pass
semver_compare() {
  local a="$1" b="$2"
  local IFS=.
  local a_parts=($a) b_parts=($b)
  local a_major=${a_parts[0]:-0} a_minor=${a_parts[1]:-0} a_patch=${a_parts[2]:-0}
  local b_major=${b_parts[0]:-0} b_minor=${b_parts[1]:-0} b_patch=${b_parts[2]:-0}

  if (( a_major != b_major )); then
    (( a_major > b_major )) && echo 1 || echo -1; return
  fi
  if (( a_minor != b_minor )); then
    (( a_minor > b_minor )) && echo 1 || echo -1; return
  fi
  if (( a_patch != b_patch )); then
    (( a_patch > b_patch )) && echo 1 || echo -1; return
  fi
  echo 0
}
```

**Verified edge cases:**

| Input A | Input B | Expected | Actual |
|---------|---------|----------|--------|
| 1.22.4 | 1.22.4 | 0 | 0 |
| 1.22.5 | 1.22.4 | 1 | 1 |
| 1.22.3 | 1.22.4 | -1 | -1 |
| 1.100.0 | 1.99.99 | 1 | 1 |
| 2.0.0 | 1.99.99 | 1 | 1 |
| 0.99.99 | 1.0.0 | -1 | -1 |

**Design decision:** Direct integer comparison (not the `* 1000000` multiplier approach from earlier research). Component-by-component comparison handles arbitrarily large version numbers without overflow risk.

### Pattern 2: Semver Validation

**What:** Regex to validate that a string is strict `MAJOR.MINOR.PATCH` before passing to arithmetic.
**Why needed:** If the VERSION file contains garbage, bash arithmetic will error. Validate first, skip check on invalid input.

```bash
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
```

**Verified:** Correctly accepts `1.22.4`, `1.100.200`. Correctly rejects `1.22`, `1.22.4-beta`, `abc`, empty string.

### Pattern 3: JSON Reading from File

**What:** Read nested fields from `gsd-compat.json` using the project's established `python3 -c` pattern.
**Verified:** Tested reading `gsd_compat.min`, `gsd_compat.max`, `gsd_compat.tested`, and `schema_version` from a file.

```bash
# Read a nested JSON field from gsd-compat.json
# Usage: GSD_MIN=$(read_compat_field "$SCRIPT_DIR/gsd-compat.json" "gsd_compat" "min")
python3 -c "import json; d=json.load(open('$COMPAT_FILE')); print(d['gsd_compat']['min'])"
```

**Note:** The file-based `json.load(open(...))` approach is correct here (reading from disk, not piped stdin). This differs slightly from the `sys.stdin` pattern used in bin/ scripts (which pipe JSON through stdin). Both patterns exist in the codebase; use file-based since `gsd-compat.json` has a known path.

### Pattern 4: VERSION File Reading

**What:** Read the GSD version from `~/.claude/get-shit-done/VERSION`.
**Verified:** The file contains exactly `1.22.4` (6 bytes, no trailing newline). `cat` returns the string cleanly.

```bash
GSD_VERSION_FILE="$HOME/.claude/get-shit-done/VERSION"
if [ -f "$GSD_VERSION_FILE" ]; then
  GSD_VERSION=$(cat "$GSD_VERSION_FILE" | tr -d '[:space:]')
fi
```

**Note on `tr -d`:** The current VERSION file has no trailing whitespace or newline, but `tr -d '[:space:]'` is a safe defensive measure in case future GSD versions change this. Cost: one extra pipe. Benefit: robustness.

## Architecture: Integration with install.sh

### Insert Point

The compat check goes between `preflight_check` call (line 121) and the skills installation (line 126). Specifically:

```
Line 121: preflight_check
Line 122: (blank)
  >>> NEW: compat_check     <<<
Line 123: # --------------------------------------------------
Line 124: # 1. Install skills into ~/.claude/skills/ (personal = all projects)
```

### Function Placement

Define `compat_check()` as a function (like `preflight_check()` and `verify_integrity()`) before its call site. Place it after `preflight_check()` definition (around line 119), before the `preflight_check` call on line 121.

### Variables Set by compat_check

The function should set module-level variables that the summary banner can reference:

```bash
GSD_VERSION=""           # Detected GSD version (empty if not found)
GSD_COMPAT_STATUS=""     # "compatible" | "outside_range" | "not_found" | "invalid"
GSD_COMPAT_MIN=""        # From gsd-compat.json
GSD_COMPAT_MAX=""        # From gsd-compat.json
GSD_COMPAT_TESTED=""     # From gsd-compat.json
```

### Summary Banner Update

The existing summary section (lines 433-462) should include the GSD compatibility result. Place it after the "Global configs:" section and before the "HOW TO USE" section.

**In-range:**
```
 GSD base: v1.22.4 (tested range: 1.20.0 - 1.99.99)
```

**Out-of-range:**
```
 GSD base: v1.19.0 (WARNING: outside tested range 1.20.0 - 1.99.99)
```

**Not found:**
```
 GSD base: not detected (will be installed in step 5)
```

### compat_check Behavior Matrix

| VERSION file exists | Version valid semver | Version in range | Action |
|---------------------|---------------------|------------------|--------|
| No | -- | -- | Skip silently (GSD gets installed in step 5) |
| Yes | No | -- | `warn()`: "VERSION file contains invalid format" |
| Yes | Yes | Yes | `ok()`: "GSD v1.22.4 -- compatible" |
| Yes | Yes | No | `warn()`: "GSD v1.25.0 outside tested range (1.20.0-1.99.99). Proceed with caution." |

**Critical:** The compat check must NOT read the manifest with `set -e` protection. If `python3` is missing or the JSON is malformed, the check should degrade gracefully (warn and continue), not abort the install. Use `|| true` or explicit error handling around the python3 call.

### python3 Availability

`python3` is NOT currently checked in install.sh's pre-flight. It is used in bin/ and test/ scripts but not in the installer itself. Adding the compat check introduces the first `python3` dependency in install.sh.

**Options:**
1. Add `python3` to pre-flight as an optional dep (warn if missing)
2. Guard the compat check with `command -v python3` and skip if missing
3. Read JSON without python3 (but this requires fragile grep/sed on nested keys)

**Recommendation:** Option 2 -- guard with `command -v python3`. If python3 is missing, skip the compat check silently. This keeps the installer robust on minimal systems. The compat check is informational, not critical-path. No need to add python3 to pre-flight for an optional feature.

## gsd-compat.json Schema

### Prescribed Schema (matches 07-CONTEXT.md decisions)

```json
{
  "schema_version": 1,
  "addon_version": "1.2.0",
  "gsd_compat": {
    "min": "1.20.0",
    "max": "1.99.99",
    "tested": "1.22.4"
  }
}
```

### Field Definitions

| Field | Type | Purpose | Mutable? |
|-------|------|---------|----------|
| `schema_version` | integer | Future-proofs the parser; check this first | Only on schema changes |
| `addon_version` | string | gsd-multi-model's own version for diagnostics | Each addon release |
| `gsd_compat.min` | string | Earliest GSD version with required APIs | When GSD drops old APIs |
| `gsd_compat.max` | string | Latest GSD version before known breaking changes | When GSD breaks something |
| `gsd_compat.tested` | string | Exact GSD version validated against | Each addon release |

### Why `1.99.99` for max

GSD is at v1.22.4. Using a tight upper bound (e.g., `1.23.0`) would trigger false warnings within days as GSD publishes 3-5 patches per week. `1.99.99` means "no known breaking change in the 1.x line." This matches the STATE.md decision: "Wide upper bound on compat range -- avoids frequent false alarms."

## Test Coverage

### Test Approach

The 07-CONTEXT.md specifies three test cases. These can be added to the existing `test-install.sh` OR as a separate function/section. Given that test-install.sh already checks file presence and integrity, adding compat tests there is natural.

### Required Test Cases

| Test | Input | Expected Output |
|------|-------|-----------------|
| In-range version | VERSION file contains `1.22.4`, range is `1.20.0 - 1.99.99` | No warning, `ok()` message |
| Out-of-range version | VERSION file contains `1.19.0`, range is `1.20.0 - 1.99.99` | Warning message, install continues |
| Missing VERSION file | No file at `~/.claude/get-shit-done/VERSION` | No warning, no error, silent skip |

### Test Implementation Strategy

The compat check runs inside `install.sh`, so the cleanest test approach is:
1. Mock the VERSION file path (set a test variable that overrides the default path)
2. Run install.sh and capture output
3. Check for presence/absence of warning strings

Alternatively, extract `semver_compare()` as a sourceable function and test it directly:
```bash
source install.sh --source-only  # (if supported)
# or: extract semver_compare into a shared lib
```

**Recommendation:** Test `semver_compare()` directly by sourcing the function definition (write a small test that copies just the function). Test the compat_check integration by running install.sh with a mocked VERSION file. The existing test-install.sh patterns (run script, check output) support this.

### Testing semver_compare Edge Cases

Beyond the three required tests, the semver_compare function should have unit-level coverage for:
- Equal versions (returns 0)
- Greater/less at each component level (major, minor, patch)
- Large component values (1.100.0 vs 1.99.99) to catch integer-packing bugs

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing | grep/sed/awk on JSON | `python3 -c "import json"` | Nested keys (`gsd_compat.min`) break with regex; 40+ call sites already use python3 pattern |
| Semver pre-release handling | Custom parser for `1.22.4-beta.1` | Nothing -- ignore pre-release | VERSION file is always `MAJOR.MINOR.PATCH`; handling pre-release adds complexity for a format that doesn't exist |
| Colored output | Custom ANSI escape codes | Existing `ok()`, `warn()` helpers | install.sh already has TTY-aware output functions with counters |

## Common Pitfalls

### Pitfall 1: set -e Kills the Install on python3 Failure

**What goes wrong:** install.sh uses `set -euo pipefail`. If `python3` is not available or `gsd-compat.json` is malformed, the subshell `$(python3 -c ...)` returns non-zero, and `set -e` aborts the entire install.
**Why it happens:** The compat check is informational, but `set -e` treats any non-zero exit as fatal.
**How to avoid:** Wrap the python3 call in explicit error handling: `GSD_MIN=$(python3 -c "..." 2>/dev/null) || { warn "Could not read gsd-compat.json"; return; }`. The `|| { ...; return; }` pattern prevents `set -e` from killing the script.
**Warning signs:** Install fails with a python3 traceback when gsd-compat.json is missing or malformed.

### Pitfall 2: IFS Contamination from semver_compare

**What goes wrong:** `semver_compare()` sets `local IFS=.` to split version strings. If `IFS` leaks out of the function scope, subsequent bash operations (word splitting, `read`, array expansion) break silently.
**Why it happens:** `local IFS=.` is function-scoped in bash, so it should NOT leak. But if someone refactors the function to inline code (removing the function wrapper), IFS contamination occurs.
**How to avoid:** Always use `local IFS=.` inside the function. Add a comment: `# IFS is local -- does not affect caller`.

### Pitfall 3: VERSION File with Unexpected Content

**What goes wrong:** The VERSION file could contain a pre-release tag (`1.22.4-beta`), extra whitespace, or multiple lines. The semver_compare function treats `1.22.4-beta` as invalid when split by `.` (the third component `4-beta` is not a valid integer).
**Why it happens:** GSD currently writes plain `MAJOR.MINOR.PATCH`, but this is not contractually guaranteed.
**How to avoid:** Validate the version string with `[[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]` before passing to semver_compare. If invalid, warn and skip the check. Strip whitespace with `tr -d '[:space:]'` before validation.

### Pitfall 4: Hardcoded VERSION Path Breaks Local Installs

**What goes wrong:** The compat check reads `~/.claude/get-shit-done/VERSION` (global install path). If the user has a local GSD install (in `./.claude/get-shit-done/VERSION`), the check reads the wrong version or reports "not found."
**Why it happens:** GSD supports multiple install locations but the addon checks only one.
**How to avoid:** For v1.2, checking the global path is explicitly scoped as sufficient (per STATE.md and research SUMMARY.md). Add a comment documenting this assumption. The 07-CONTEXT.md decision says "skip silently" if VERSION doesn't exist, which handles this case gracefully.

## Code Examples

### Complete compat_check Function (Prescriptive Reference)

This is the verified implementation pattern combining all researched elements:

```bash
# --- GSD compatibility check ---
compat_check() {
  local version_file="$HOME/.claude/get-shit-done/VERSION"
  local compat_file="$SCRIPT_DIR/gsd-compat.json"

  # Skip if VERSION file doesn't exist (GSD gets installed in step 5)
  if [ ! -f "$version_file" ]; then
    GSD_COMPAT_STATUS="not_found"
    return
  fi

  # Read and validate VERSION
  GSD_VERSION=$(cat "$version_file" | tr -d '[:space:]')
  if ! [[ "$GSD_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    warn "GSD VERSION file contains invalid format: $GSD_VERSION"
    GSD_COMPAT_STATUS="invalid"
    return
  fi

  # Read compat range from manifest (requires python3)
  if ! command -v python3 &>/dev/null; then
    GSD_COMPAT_STATUS="not_found"
    return
  fi

  GSD_COMPAT_MIN=$(python3 -c "import json; print(json.load(open('$compat_file'))['gsd_compat']['min'])" 2>/dev/null) || { GSD_COMPAT_STATUS="invalid"; return; }
  GSD_COMPAT_MAX=$(python3 -c "import json; print(json.load(open('$compat_file'))['gsd_compat']['max'])" 2>/dev/null) || { GSD_COMPAT_STATUS="invalid"; return; }
  GSD_COMPAT_TESTED=$(python3 -c "import json; print(json.load(open('$compat_file'))['gsd_compat']['tested'])" 2>/dev/null) || { GSD_COMPAT_STATUS="invalid"; return; }

  # Compare
  local cmp_min cmp_max
  cmp_min=$(semver_compare "$GSD_VERSION" "$GSD_COMPAT_MIN")
  cmp_max=$(semver_compare "$GSD_VERSION" "$GSD_COMPAT_MAX")

  echo "==> Checking GSD compatibility..."
  if (( cmp_min >= 0 && cmp_max <= 0 )); then
    ok "GSD v${GSD_VERSION} -- compatible"
    GSD_COMPAT_STATUS="compatible"
  else
    warn "GSD v${GSD_VERSION} outside tested range (${GSD_COMPAT_MIN}-${GSD_COMPAT_MAX}). Proceed with caution."
    GSD_COMPAT_STATUS="outside_range"
  fi
  echo ""
}
```

**Note:** This is a reference implementation for the planner, not final code. The executor should follow this pattern but may adjust formatting to match the exact style of existing install.sh functions.

## State of the Art (2026)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `sort -V` for version comparison | Pure bash arithmetic | Always preferred in portable scripts | `sort -V` unavailable on some BSD/older macOS |
| `jq` for JSON in shell scripts | `python3 -c "import json"` | Project convention since v1.0 | No new dependency; python3 ships with macOS and Linux |
| Hard-fail on version mismatch | Warn-only | Project decision in STATE.md | Users stay in control; overlay pattern means files likely still work |

## Open Questions

1. **Optimal python3 call count:** The reference implementation makes 3 separate `python3 -c` calls to read 3 fields. This could be collapsed into a single call that outputs all 3 fields. Trade-off: one call is faster but harder to error-handle per-field. For ~10ms savings on a human-interactive install, separate calls are clearer. **Recommendation:** Use separate calls for clarity unless profiling shows a problem.

2. **Where to put semver_compare tests:** The 07-CONTEXT.md says "add test cases to test suite for: in-range, out-of-range, missing VERSION." It leaves discretion on whether to add to `test-install.sh` or create a separate file. **Recommendation:** Add a new `=== Checking GSD compatibility ===` section to `test-install.sh` since that file already tests install.sh behavior. Unit tests for `semver_compare` itself can be inline (source the function and call it with known inputs).

3. **gsd-compat.json checked_interfaces field:** The ARCHITECTURE.md research included a `checked_interfaces` array for documentation. The 07-CONTEXT.md schema does not include it. **Recommendation:** Omit it. The schema should be minimal per the CONTEXT decisions. The 5 fields specified (addon_version, gsd_compat.min, gsd_compat.max, gsd_compat.tested, schema_version) are sufficient.

## Sources

### Primary (HIGH confidence)
- **install.sh** (468 lines) -- Read in full. Verified line numbers, function structure, variable naming, output patterns, ANSI color helpers, counter system, summary banner format.
- **test-install.sh** (103 lines) -- Read in full. Verified test patterns (check/check_integrity functions, section headers, pass/fail/warn counters).
- **~/.claude/get-shit-done/VERSION** -- Inspected on disk. Confirmed format: 6 bytes, `1.22.4`, no trailing newline.
- **07-CONTEXT.md** -- All user decisions verified and incorporated.

### Secondary (HIGH confidence)
- **v1.2 project research** (SUMMARY.md, STACK.md, ARCHITECTURE.md, PITFALLS.md) -- Comprehensive project-level research from 2026-03-05. Findings verified and refined for phase-level specificity.
- **STATE.md** -- Project decisions confirmed: warn-only, install-time only, wide upper bound.
- **REQUIREMENTS.md** -- COMPAT-01, COMPAT-02, COMPAT-03 confirmed as phase scope.

### Experimental (HIGH confidence)
- **Bash semver comparison** -- Tested interactively with 10 edge cases. All passed. Component-by-component integer comparison confirmed correct for arbitrarily large version numbers.
- **python3 JSON file reading** -- Tested reading nested fields from a temp file matching the exact gsd-compat.json schema. Confirmed working.
- **Semver validation regex** -- Tested with 6 inputs (valid and invalid). All correctly classified.
- **VERSION file byte inspection** -- Used `xxd` to confirm exact contents (no hidden whitespace).

## Metadata

**Confidence breakdown:**
- semver_compare implementation: HIGH -- experimentally verified with edge cases
- gsd-compat.json schema: HIGH -- matches 07-CONTEXT.md decisions and project research
- install.sh integration: HIGH -- line numbers, function structure, and insert point verified from source
- Test approach: MEDIUM -- clear direction but test file organization is discretionary
- python3 fallback behavior: HIGH -- verified `command -v python3` guard pattern

**Research date:** 2026-03-06
**Valid until:** Indefinite (bash arithmetic and JSON parsing are stable; no external dependencies to version-drift)

---
*Phase: 07-compatibility-manifest-install-time-check*
*Research completed: 2026-03-06*
