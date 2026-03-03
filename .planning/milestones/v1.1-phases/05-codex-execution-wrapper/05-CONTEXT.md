# Phase 5: Codex Execution Wrapper - Context

**Gathered:** 2026-03-03
**Status:** Ready for planning

<domain>
## Phase Boundary

A shell script (`bin/codex-task.sh`) that reads task specs from PLAN.md XML blocks, invokes Codex CLI with injected context, and outputs structured results. One task per invocation. Phase 4 worktree scripts handle isolation; Phase 6 demo consumes this script's output.

</domain>

<decisions>
## Implementation Decisions

### Context Injection
- Pass task description from XML block + `files_modified` list from plan frontmatter — Codex reads the files itself in sandbox
- Append CLAUDE.md / AGENTS.md project instructions if they exist — Codex follows same coding conventions
- Auto-create worktree via `bin/worktree-create.sh` before invoking Codex, cleanup after — full automation in one command
- One task per Codex run — caller (execute-phase) handles looping/parallelization

### Task Extraction from PLAN.md
- Select task by explicit number: `bin/codex-task.sh --plan 04-01-PLAN.md --task 1`
- Validate executor attribute — warn if task not marked `executor="codex"`, allow override with `--force`
- Parse XML task blocks with shell tools (grep/sed/awk) — no external parser dependencies
- Confidence level affects Codex invocation mode: high → `--full-auto`, medium → default approval, low → warn and skip

### Structured Output Format
- JSON output by default: `{"exit_code": 0, "changed_files": [...], "commit_hash": "abc123", "task_id": "04-01-T1", "duration_seconds": N, "plan": "...", "executor": "codex", "confidence": "high"}`
- Include: Codex stdout/stderr capture, duration, task metadata echo, diff summary (insertions/deletions per file)
- Human-readable summary on stderr
- Auto-commit Codex's changes with structured message (e.g. `feat(04-01-T1): [task name]`) — commit hash goes in report

### Error Handling & Timeouts
- Configurable timeout: `--timeout 300` (default 5 min), kill Codex process after timeout
- No retries — fail fast, let caller decide whether to retry or escalate
- Distinct exit codes: 0=success, 1=codex failure, 2=parse error, 3=timeout, 4=pre-flight failure
- Pre-flight check for `codex` in PATH — actionable install message if missing
- Support `--dry-run` flag to print what would be run without executing (works without Codex installed)

### Claude's Discretion
- Exact Codex CLI flags beyond `--full-auto`
- How to capture and structure Codex stdout/stderr (tee, temp files, etc.)
- Worktree cleanup behavior on Codex failure (keep for debugging vs always clean)
- Prompt template formatting for the Codex invocation

</decisions>

<specifics>
## Specific Ideas

- Should feel like a standard task runner — `bin/codex-task.sh --plan PLAN.md --task N` is the core interface
- SPEC.md shows the intended pattern: `codex --full-auto "task description"` — this script wraps that with context injection and structured output
- Phase 6 (E2E Demo) will call this script programmatically and validate its JSON output
- The `codex-review` skill already exists for cross-model review — this script is the execution counterpart

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `bin/worktree-create.sh`: Auto-create worktree with `--json` output — codex-task.sh can parse this to get worktree path
- `bin/worktree-cleanup.sh`: Auto-cleanup with merge-back — codex-task.sh calls this after Codex completes
- `bin/worktree-list.sh`: List active worktrees — useful for debugging/status
- `skills/codex-review/SKILL.md`: Shows Codex CLI invocation patterns and argument parsing

### Established Patterns
- Phase 4 scripts use `--json` flag for machine-readable output — codex-task.sh follows same pattern
- Phase 4 scripts use distinct exit codes per failure type — codex-task.sh extends this convention
- Phase 4 scripts use pre-flight validation checks — codex-task.sh follows same safety pattern
- `~/.codex/config.toml` configures Codex model, approval policy, sandbox mode

### Integration Points
- `bin/codex-task.sh` calls `bin/worktree-create.sh --json` to get worktree path
- `bin/codex-task.sh` calls `bin/worktree-cleanup.sh` after Codex completes
- Execute-phase orchestrator calls `bin/codex-task.sh` for tasks with `executor="codex"`
- Phase 6 demo script calls `bin/codex-task.sh` and validates JSON output

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 05-codex-execution-wrapper*
*Context gathered: 2026-03-03*
