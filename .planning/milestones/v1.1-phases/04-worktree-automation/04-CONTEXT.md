# Phase 4: Worktree Automation - Context

**Gathered:** 2026-03-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Shell scripts (`bin/worktree-create.sh`, `bin/worktree-cleanup.sh`) that create and tear down isolated git worktrees for parallel Codex execution. Users can create a worktree, run Codex in it, and merge changes back — all with single commands. Phase 5 (Codex Execution Wrapper) will call these scripts programmatically.

</domain>

<decisions>
## Implementation Decisions

### Branch Naming & Lifecycle
- Auto-generate branch names from phase/task context (e.g. `gsd/phase-04/task-02`)
- Accept optional `--task path/to/PLAN.md` argument to derive name from plan file
- Fall back to phase-based default if no task ref provided
- Worktree directories created as siblings to main repo (e.g. `../gsd-worktree-phase04-task02`)
- Branches deleted after successful merge — keep branch list clean

### Merge-back Strategy
- Use regular merge commits (preserves full worktree commit history, easy to revert)
- On merge conflicts: abort the merge, print conflicting files, tell user to resolve manually — never auto-resolve
- Require clean working tree in main repo before merging back (strict — user stashes or commits first)
- Support `--no-merge --force` to discard worktree without merging (for throwaway experiments, no interactive prompt)

### Output & Feedback
- On create success: print summary block (worktree path, branch name, base commit, `cd <path>` hint)
- On cleanup success: print merge summary (files changed, insertions/deletions, merge commit hash)
- Support `--json` flag for machine-readable output — Phase 5's Codex wrapper parses this directly
- Errors to stderr with distinct exit codes per failure type (1=dirty tree, 2=branch exists, 3=merge conflict)

### Safety Guardrails
- Pre-flight checks on create: verify git repo, clean working tree, branch name available, no existing worktree at target path
- Soft limit on concurrent worktrees: warn after 3-5 active but allow creation
- Include `bin/worktree-list.sh` helper to show active worktrees with branch, path, and age
- Support `--all` flag on cleanup to tear down all GSD-created worktrees (sequential merge)

### Claude's Discretion
- Exact branch name format and collision-avoidance suffix
- Worktree directory naming convention details
- Internal implementation of pre-flight check ordering
- Whether to support `--base <commit>` for creating worktrees from non-HEAD commits

</decisions>

<specifics>
## Specific Ideas

- Scripts should feel like standard git tooling — familiar to developers who know `git worktree`
- Must work in CI/automation context (exit codes, no interactive prompts unless --force absent on destructive ops)
- Phase 5 (Codex wrapper) is the primary programmatic consumer — `--json` output designed for it
- The SPEC.md already shows the intended usage pattern: `git worktree add ../task-codex codex-branch` style

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `install.sh`: Existing installer pattern with idempotent checks — similar safety patterns apply to worktree scripts
- `test-install.sh`: Test harness pattern that can be adapted for worktree integration tests

### Established Patterns
- Bash scripts in project root (`install.sh`, `test-install.sh`) — new scripts go in `bin/`
- Skills pattern in `skills/` — worktree scripts are utilities, not skills
- Error handling in `install.sh` uses basic conditionals and echo — worktree scripts should follow similar shell style

### Integration Points
- `bin/worktree-create.sh` and `bin/worktree-cleanup.sh` will be called by Phase 5's `bin/codex-task.sh`
- `bin/worktree-list.sh` is standalone utility
- `docs/SPEC.md` section 6 describes the intended parallel execution workflow these scripts enable

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-worktree-automation*
*Context gathered: 2026-03-03*
