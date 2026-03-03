# Phase 6: End-to-End Demo - Context

**Gathered:** 2026-03-03
**Status:** Ready for planning

<domain>
## Phase Boundary

A single demo script (`bin/demo.sh`) proves the full dual-tool workflow loop runs end-to-end: init-gsd bootstrap, plan creation with task routing, worktree creation, Codex execution (dry-run by default), merge-back, and cross-review validation. The demo uses a shipped fixture project and runs in a temp directory sandbox.

</domain>

<decisions>
## Implementation Decisions

### Demo scope & stages
- Default to dry-run mode (codex-task.sh --dry-run); --live flag for real Codex execution
- Full loop: init-gsd bootstrap -> plan creation -> task splitting -> worktree create -> codex-task execution -> worktree cleanup/merge -> cross-review validation
- Use a pre-built fixture project shipped in the repo (not generated on the fly)
- Cross-review stage validates artifacts exist structurally (commits, changed files, structured JSON) rather than invoking both tools live

### Output & reporting
- Stage banners matching existing GSD ANSI patterns (GSD > STAGE NAME) with brief status per step
- Final summary table showing each stage with pass/fail status, duration, and list of artifacts produced
- --json flag for machine-readable output (human to stderr, JSON to stdout), consistent with codex-task.sh and worktree scripts
- Script named `bin/demo.sh`

### Demo environment
- Create sandbox in /tmp/gsd-demo-XXXX temp directory
- Auto-clean temp dir on success, keep on failure for debugging (show path)
- --keep flag to preserve temp dir even on success (for inspection)
- Fixture project files live in test/fixtures/demo-project/
- Demo requires install.sh to have been run first (pre-flight check, not self-contained)

### Failure handling
- Abort immediately on first stage failure (stages are dependent, continuing would mislead)
- Exit code: 0 on success, 1 on failure (matches test-install.sh convention)
- Pre-flight checks for git, node, and installed GSD skills before starting
- Summary output identifies which stage failed and why

### Claude's Discretion
- Fixture project content (minimal files with a TODO task suitable for Codex)
- Exact stage banner formatting and timing display
- Internal helper function structure
- How to simulate init-gsd bootstrap in a scripted context

</decisions>

<specifics>
## Specific Ideas

- Both --dry-run (default) and --live modes via flag, so demo works without Codex CLI installed
- Follow the ANSI color + TTY detection pattern established in install.sh and bin/ scripts
- Summary table should list artifacts produced (files created, commits made, worktrees used)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `bin/codex-task.sh`: Full Codex task runner with --dry-run, --timeout, --force, --json, structured JSON output, exit code contract (0-4)
- `bin/worktree-create.sh`: Worktree creation with --task, --json, --base flags
- `bin/worktree-cleanup.sh`: Worktree removal with merge-back, conflict detection, batch cleanup
- `bin/worktree-list.sh`: List active worktrees
- `skills/init-gsd/SKILL.md`: Project bootstrapping (creates AGENTS.md, CLAUDE.md, .claude/rules/, Codex config)
- `install.sh`: Pre-flight checks, ANSI output, --force flag pattern
- `test-install.sh`: Integrity verification pattern

### Established Patterns
- ANSI color helpers with TTY detection (if [ -t 2 ]; then ...)
- set -euo pipefail in all scripts
- Human output to stderr, JSON to stdout for --json flag
- Exit code contracts documented in script headers
- Pre-flight dependency checks before main logic

### Integration Points
- Demo calls bin/worktree-create.sh, bin/codex-task.sh, bin/worktree-cleanup.sh directly
- Fixture project needs a PLAN.md with XML task blocks (executor/confidence attributes) for codex-task.sh to parse
- init-gsd creates .claude/ and AGENTS.md which later stages validate

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 06-end-to-end-demo*
*Context gathered: 2026-03-03*
