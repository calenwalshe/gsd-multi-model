# Phase 09: Local-First Install - Context

**Gathered:** 2026-03-08
**Status:** Partially gathered (CLAUDE.md content area still to discuss)

<domain>
## Phase Boundary

Modify `/init-gsd` to scaffold project-local config files with absolute repo paths, skipping global modifications when base GSD is detected. Users can test the dual-tool workflow in a single project without touching their working global GSD setup.

</domain>

<decisions>
## Implementation Decisions

### Detection strategy
- Auto-detect base GSD by checking if `~/.claude/get-shit-done/` directory exists
- If detected, run in local-only mode automatically (no `--local` flag needed)
- Print one-liner status: `✓ Base GSD detected — running in local-only mode`

### Global step handling
- When base GSD detected, skip ALL global steps: Step 6 (Codex config), Step 7 (global CLAUDE.md), Step 8 (GSD install)
- In the final summary (Step 10), show a "Skipped: global config (base GSD detected)" section alongside created/skipped project files

### Bin path resolution
- Auto-discover gsd-multi-model repo location via breadcrumb file
- `install.sh` writes a breadcrumb JSON file at `~/.claude/skills/init-gsd/.gsd-multi-model-origin` with `{"repo_path": "/path/to/gsd-multi-model"}` during skill install
- `/init-gsd` reads this breadcrumb to resolve absolute paths to bin/ scripts
- Store resolved repo path in project-local `.claude/gsd-multi-model.json` so other skills can find it too
- If breadcrumb is stale (repo moved/deleted): warn and skip bin path config, don't hard fail

### CLAUDE.md content
- **NOT YET DISCUSSED** — resume discussion here

### Claude's Discretion
- Exact breadcrumb JSON schema fields
- Whether `.claude/gsd-multi-model.json` also stores addon version info
- Error message wording for stale breadcrumb

</decisions>

<specifics>
## Specific Ideas

- Reuse existing `ok()`/`warn()` helpers from install.sh for consistency
- Breadcrumb pattern mirrors the existing `gsd-compat.json` approach — simple JSON, committed at install time
- The user's primary concern: zero risk to their working GSD setup

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `install.sh`: Has `ok()`/`warn()`/`err()` helpers, ANSI colors, `--force` flag, counters, summary banner
- `skills/init-gsd/SKILL.md`: 10-step skill with idempotency checks per file
- Existing Steps 3-5 already write project-local files (AGENTS.md, CLAUDE.md, .claude/rules/)

### Established Patterns
- Non-destructive install: skip existing unless `--force`
- Skills copied to `~/.claude/skills/` by install.sh (not symlinked)
- `python3 -c "import json; ..."` for JSON parsing in bash scripts

### Integration Points
- `install.sh` Step 1 (skills install loop): Add breadcrumb write after each skill copy
- `init-gsd` SKILL.md Step 1: Add detection check before Step 6
- New file: `.claude/gsd-multi-model.json` in target projects

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 09-local-first-install*
*Context gathered: 2026-03-08 (partial — CLAUDE.md content area remaining)*
