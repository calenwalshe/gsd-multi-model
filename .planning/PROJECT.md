# gsd-multi-model

## Vision
A full framework for multi-model AI development that combines Claude Code (planner/orchestrator) and Codex CLI (builder/executor) into a unified, spec-driven workflow. Installed via a single `/init-gsd` slash command inside Claude Code.

## Problem
Developers using both Claude Code and Codex CLI lack a structured way to combine them. Each session requires re-explaining the workflow, tasks aren't automatically split by tool strengths, and there's no cross-model verification. Work is ad-hoc rather than repeatable.

## Solution
A bootstrap package that installs skills, custom GSD agents, orchestration logic, task splitting heuristics, and worktree management. One command (`/init-gsd`) wires up any project with the dual-tool workflow — Claude plans and handles complexity, Codex executes autonomously in parallel, both verify each other's work.

## Core Features
1. **`/init-gsd` bootstrap** — Creates AGENTS.md, CLAUDE.md, .claude/rules/, git init from within Claude Code
2. **Automatic task splitting** — Heuristic during /gsd:plan-phase: multi-file/architecture → Claude, CRUD/tests/scripts → Codex; user can override
3. **Codex worktree execution** — Auto-create git worktree, run `codex --full-auto` with task prompt, merge back
4. **Cross-model verification** — `/gsd-codex-verify` runs GSD verifier then Codex review; each tool reviews the other's output
5. **Global skills** — `/codex-review` and `/gsd-codex-verify` available across all projects
6. **Anti-context-rot** — Fresh subagent per task, .planning/ as persistent source of truth

## Target Users
Developers who use both Claude Code and Codex CLI and want a repeatable harness to combine them without re-explaining every session.

## Success Criteria
End-to-end demo: `/init-gsd` → plan a feature → auto-split tasks → Codex builds in worktree → cross-review works. The full loop must function without manual intervention beyond initial project decisions.

## Tech Stack
- Claude Code (CLI) — planning, orchestration, complex implementation
- Codex CLI — autonomous execution, cross-model review
- GSD framework — spec-driven meta-prompting, state management
- Git worktrees — parallel isolated execution
- Bash — installation, worktree management scripts

## Scope Boundaries
- **In scope**: Claude + Codex integration only
- **Out of scope**: Gemini, OpenCode, or other AI tool integration
- **Deliverable**: Full framework — skills, custom GSD agents, orchestration logic, task splitting, worktree management
