# Phase 1: Core Skill Implementation - Context

**Gathered:** 2026-03-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Implement the three custom Claude Code skills (`/init-gsd`, `/codex-review`, `/gsd-codex-verify`) so they execute end-to-end reliably. The SKILL.md files already contain detailed step-by-step instructions — this phase refines them into working, production-quality prompts with proper Codex invocation, error handling, idempotency, and output formatting.

</domain>

<decisions>
## Implementation Decisions

### Codex Invocation Method
- Use `codex exec --full-auto` for all automated Codex calls (non-interactive, fire-and-forget)
- `/gsd-codex-verify` uses `--json` flag for structured JSONL parsing (pass/fail detection)
- `/codex-review` uses plain text stdout for human-readable display
- Timeout is configurable via `.planning/config.json` with `codex.timeout_seconds` key, default 5 minutes
- When Codex CLI is not installed or API key missing: graceful skip with warning, GSD verification runs solo

### Skill Completeness
- Quality bar: PRODUCTION-GRADE — handle all realistic failure modes (missing deps, partial installs, network timeouts, conflicting configs, interrupted runs)
- Clear error recovery for each failure mode — skills should never leave things in a broken state
- No silent failures — every error path produces an actionable message
- `/init-gsd` auto-chains to `/gsd:new-project` with user prompt ("Run /gsd:new-project now?")
- `/codex-review` diff scope: last N commits (default 5), user can pass `--commits=N` to adjust
- `/gsd-codex-verify` writes VERIFICATION.md AND displays results inline (both)

### Idempotency & Existing Projects
- `/init-gsd` default behavior: skip existing files, create missing ones — never overwrite user customizations
- Support `--force` flag to overwrite everything when user explicitly wants to reset
- Stack detection: read package.json / pyproject.toml / Makefile to fill in Build & Test commands in AGENTS.md
- Scope: create both project-local files AND global configs (Codex config.toml, ~/.claude/CLAUDE.md) if missing
- Print summary showing what was created vs skipped

### Output & Result Formatting
- Codex review findings displayed as structured report blocks with severity levels (CRITICAL/WARNING/INFO)
- Use the `═══` border format from the spec for combined verification reports
- On FAIL: report only — show what failed, user decides next action (no auto-generated fix tasks)
- Raw Codex output in appendix: Claude's discretion based on output length and relevance

### Claude's Discretion
- Exact error message wording
- How to handle partial Codex responses (timeout mid-review)
- Whether to retry Codex on transient failures or fail immediately
- Stack detection depth (how many config files to check)

</decisions>

<specifics>
## Specific Ideas

- Skills are prompt-based (SKILL.md IS the implementation via `disable-model-invocation: true`)
- Codex sandbox protects `.planning/` and `.git/` automatically in `workspace-write` mode — no extra guards needed
- `codex exec --ephemeral` prevents session file persistence — use for CI/automation contexts
- JSONL events to parse for verification: `turn.completed`, `error`, `item.file_write`

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `skills/init-gsd/SKILL.md` (236 lines): Complete 9-step bootstrap spec — needs Codex invocation refinement and idempotency logic
- `skills/codex-review/SKILL.md` (72 lines): 5-step review flow — needs `codex exec` migration and error handling
- `skills/gsd-codex-verify/SKILL.md` (92 lines): 7-step combined verification — needs JSON parsing and report file writing
- `global/codex-config.toml`: Codex config template with model and sandbox settings
- `global/codex-agents.md`: Global Codex instructions template

### Established Patterns
- Skills use YAML frontmatter: `name`, `description`, `disable-model-invocation`, `argument-hint`, `allowed-tools`
- All skills set `disable-model-invocation: true` — Claude reads and follows instructions
- `.claude/rules/` provides conditional context injection scoped by file paths

### Integration Points
- Skills installed to `~/.claude/skills/` by `install.sh`
- GSD state in `.planning/` is the shared context both tools read
- `install.sh` and `test-install.sh` need updates to cover refined skills

</code_context>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-core-skill-implementation*
*Context gathered: 2026-03-02*
