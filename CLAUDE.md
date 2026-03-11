# gsd-multi-model — Claude Code Instructions

See @AGENTS.md for build commands, architecture, and conventions.

## GSD Workflow

- Run `/gsd:status` at the start of every session to orient yourself
- Follow: `/gsd:discuss-phase` → `/gsd:plan-phase` → `/gsd:execute-phase` → `/gsd:verify-work`
- Use subagents strategically: haiku for research, sonnet for implementation, opus for planning/review

## Dual-Tool Execution

During execute phase, split tasks by complexity:
- Claude Code: complex multi-file changes, architecture, interactive work
- Codex (in parallel worktree): autonomous tasks, CRUD, tests, scripts, CLI tools
- Run `codex --full-auto "task description"` in a separate worktree for autonomous work

## Dual-Tool Verification (Cross-Review)

After execution, each tool reviews the OTHER's work:
- Run `/gsd-codex-verify` for combined verification
- Claude verifies Codex's autonomous output against specs
- Codex reviews Claude's complex changes for blind spots
Only advance phases after both verification layers pass.

## Quality Gates

- Never skip verification
- If verification fails, fix in a new task — don't patch inline
- Every task = one atomic commit
