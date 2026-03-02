# Phase 3: Installer Hardening & Global Config - Context

**Gathered:** 2026-03-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Harden `install.sh` with dependency pre-flight checks, post-install integrity validation, and non-destructive global config templates for Claude and Codex. This phase improves the existing installer — it does not add new installation targets or change what gets installed.

</domain>

<decisions>
## Implementation Decisions

### Dependency checking
- Required deps: git, node (hard fail if missing)
- Optional deps: claude CLI, codex CLI (warn with install link, continue)
- Presence-only checks (`command -v`), no version minimums
- Check ALL deps first, collect failures, report summary at end (not fail-on-first)

### Error messaging style
- Error format: name + platform-specific install command (e.g., "✗ git not found. Install: brew install git (macOS) / apt install git (Linux)")
- ANSI color output: red for errors, green for success, yellow for warnings
- TTY detection: fall back to plain text when piped or in CI (`[ -t 1 ]`)
- Preserve existing output style: ═══ banners, ==> section headers, 4-space indented items
- Always show end summary: N installed, N skipped, N warnings, N errors

### Integrity validation
- File-by-file diff after install: compare each installed file against its source
- Built into install.sh as a final verification pass (not a separate step)
- Distinguish copies vs templates: skills (direct copies) → fail on mismatch; configs (templates) → warn on mismatch
- Upgrade test-install.sh to also do diff-based integrity checks (not just existence)

### Config merge strategy
- Unified skip-if-exists for ALL config files (CLAUDE.md, codex AGENTS.md, config.toml, rules)
- Remove current grep-and-append behavior for CLAUDE.md — treat it like other configs
- Add `--force` flag: overwrites all configs with fresh templates (clean reinstall)
- When skipping existing config, just say "✓ ~/.codex/config.toml exists, skipping"
- Keep global config templates minimal as-is — don't add more settings

### Claude's Discretion
- Exact platform detection logic (macOS vs Linux vs other)
- How to structure the pre-flight check function
- Diff implementation details (cmp, diff, or custom)
- Whether --force backs up existing configs before overwriting

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `install.sh` (226 lines): Working installer with 7 sections — add pre-flight and post-install around existing logic
- `test-install.sh` (51 lines): Existence-based checker with pass/fail counting — extend with diff checks
- `global/codex-agents.md`: Codex instructions template (27 lines)
- `global/codex-config.toml`: Codex config template (15 lines)

### Established Patterns
- Section headers use `==>` prefix with 4-space indented items
- Banners use `═══` double-line box characters
- Skills are copied with `cp -r`, configs use conditional logic
- `set -euo pipefail` used in both scripts

### Integration Points
- Pre-flight checks go before section 1 (skill installation)
- Integrity validation goes after section 6 (before summary)
- test-install.sh `check()` function needs diff variant alongside existence check
- --force flag needs to be parsed before section 1

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-installer-hardening-global-config*
*Context gathered: 2026-03-02*
