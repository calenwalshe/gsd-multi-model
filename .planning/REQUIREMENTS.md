# Requirements — gsd-multi-model

## R1: /init-gsd Skill Implementation
**Priority**: CRITICAL
**Source**: PROJECT.md, SPEC.md §1-2
- `/init-gsd` must bootstrap any new project from within Claude Code
- Creates: AGENTS.md, CLAUDE.md, .claude/rules/, git init, .planning/ scaffold
- Must be idempotent (safe to re-run on existing projects)
- Reads project directory to detect existing stack/framework
- UAT: Run `/init-gsd` in empty dir → all files created, GSD workflow ready

## R2: /codex-review Skill Implementation
**Priority**: CRITICAL
**Source**: PROJECT.md, SPEC.md §4
- Cross-model review: invokes `codex exec` to review Claude's changes
- Accepts optional focus area parameter (e.g., "security", "performance")
- Captures Codex output and presents findings inline
- UAT: Run `/codex-review` after code changes → Codex produces review, findings displayed

## R3: /gsd-codex-verify Skill Implementation
**Priority**: CRITICAL
**Source**: PROJECT.md, SPEC.md §4
- Combined verification gate: runs GSD verifier then Codex cross-review
- Produces structured PASS/FAIL report
- Must check both structural compliance and code quality
- UAT: Run `/gsd-codex-verify` → combined report with clear pass/fail status

## R4: Task-Splitting Heuristic
**Priority**: HIGH
**Source**: PROJECT.md, SPEC.md §3-4
- Auto-classify tasks during /gsd:plan-phase as `claude` or `codex`
- Signals for Codex routing: single-file, CRUD, tests, scripts, clear spec, no user input needed
- Signals for Claude routing: multi-file, architecture, refactoring, ambiguous, needs interaction
- User can override any classification
- Tags stored in PLAN.md XML task elements (e.g., `<task executor="codex">`)
- UAT: Plan a mixed feature → tasks correctly tagged; overrides work

## R5: Worktree Automation
**Priority**: HIGH
**Source**: PROJECT.md, SPEC.md §6
- Script to auto-create git worktree for Codex tasks
- Naming convention: `../gsd-codex-{task-id}`
- Auto-run `codex exec --full-auto --ephemeral` in worktree
- Capture JSONL output for verification
- Merge-back: merge worktree branch into main branch after verification
- Cleanup: prune worktree after successful merge
- UAT: Execute Codex task → worktree created, code written, merged back, cleaned up

## R6: Codex Execution Wrapper
**Priority**: HIGH
**Source**: Research (codex-cli-integration.md)
- Shell script (`bin/codex-task.sh`) wrapping Codex fire-and-forget execution
- Flags: `--full-auto --ephemeral --json`
- Task prompt derived from PLAN.md (never free-form)
- JSONL output parsing for error detection and file-change tracking
- Protected-path verification (no .planning/, .git/ modifications)
- UAT: Run wrapper with task → executes in worktree, JSONL captured, errors surfaced

## R7: End-to-End Demo
**Priority**: MEDIUM
**Source**: PROJECT.md success criteria
- Complete workflow demo: /init-gsd → plan → auto-split → Codex builds → cross-review
- Documents the full loop with real output
- Validates all components work together
- UAT: Full loop completes without manual intervention beyond initial project decisions

## R8: Installer Hardening
**Priority**: MEDIUM
**Source**: Research (existing-codebase.md)
- install.sh handles missing dependencies gracefully
- Detects and reports missing `codex` CLI
- Verifies GSD framework availability
- test-install.sh covers new components (wrapper scripts, worktree helpers)
- UAT: Fresh install on clean system → all tests pass, clear error for missing deps

## R9: Global Config Templates
**Priority**: LOW
**Source**: SPEC.md §1
- ~/.codex/config.toml with correct model, approval_policy, fallback filenames
- ~/.claude/CLAUDE.md with GSD workflow instructions
- Templates versioned and installable via install.sh
- UAT: After install, both tools read shared project context correctly
