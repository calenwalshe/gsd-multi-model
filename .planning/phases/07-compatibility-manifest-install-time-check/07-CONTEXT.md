# Phase 7: Compatibility Manifest & Install-Time Check - Context

**Gathered:** 2026-03-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Create a `gsd-compat.json` manifest that declares the tested GSD version range, add a semver comparison function and compatibility check to `install.sh`, and add test coverage. Users get install-time feedback when their GSD version is outside the tested range.

</domain>

<decisions>
## Implementation Decisions

### Warning behavior
- Soft warning only — yellow one-liner, install always continues (never blocks)
- Warning text format: `⚠ GSD v1.25.0 outside tested range (1.22.0–1.24.x). Proceed with caution.`
- Same warning regardless of direction (too old or too new)
- Exit code stays 0 — compat warning does not change install exit status
- Compat warning increments the existing WARNINGS counter (shows in summary)
- When GSD version IS in range, always show: `✓ GSD v1.22.4 — compatible`
- Include tested GSD range in the install summary banner at the bottom

### Check placement
- Runs after `preflight_check`, before skills install (step 1)
- One check only — no re-check after GSD install in step 5
- If `~/.claude/get-shit-done/VERSION` doesn't exist: skip compat check silently (GSD gets installed later)

### Test coverage
- Add test cases to test suite for: in-range version, out-of-range version, missing VERSION file

### Claude's Discretion
- Exact `gsd-compat.json` schema fields (addon_version, min, max, tested, schema_version)
- Semver comparison implementation details (pure bash arithmetic)
- Whether to add tests to existing `test-install.sh` or create a separate test file
- Where exactly in the summary banner to show the GSD range

</decisions>

<specifics>
## Specific Ideas

- Use the existing `ok()`/`warn()` helpers from install.sh — no new output patterns
- `gsd-compat.json` is a static file committed to the repo (never written at runtime)
- Semver comparison via pure bash arithmetic: split MAJOR.MINOR.PATCH, compare as integers
- No `sort -V` (macOS portability), no `jq` (not default on macOS), use `python3 -c` for JSON reading (matching 40+ existing call sites in the codebase)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `install.sh` (468 lines): Has `ok()`/`warn()`/`err()` helpers, ANSI colors with TTY detection, `--force` flag, WARNINGS counter, summary banner
- `preflight_check()`: Pre-flight dependency check function — compat check goes right after this
- `verify_integrity()`: Existing integrity verification function that could inform test patterns

### Established Patterns
- All install steps use numbered sections with `==> Step description...` headers
- ANSI colors with TTY detection (RED/GREEN/YELLOW/BOLD/RESET)
- Skip-if-exists with `--force` override for non-destructive install
- Summary banner with counters: `$INSTALLED installed, $SKIPPED skipped, $WARNINGS warnings, $ERRORS errors`
- `python3 -c "import json; ..."` for JSON parsing throughout bin/ scripts

### Integration Points
- New compat check function slots between `preflight_check` (line 121) and skills install (line 126)
- `gsd-compat.json` lives in repo root alongside `install.sh`
- GSD VERSION file at `~/.claude/get-shit-done/VERSION` (simple semver string, e.g. `1.22.4`)

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-compatibility-manifest-install-time-check*
*Context gathered: 2026-03-06*
