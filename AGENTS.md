# gsd-multi-model

A multi-model integrated development system that combines GSD (Get Shit Done), Claude Code, and Codex CLI into a unified spec-driven workflow.

## Build & Test

- `bash install.sh` — install skills, global configs, and GSD across all runtimes
- `bash test-install.sh` — verify installation integrity

## Architecture

- `skills/` — Claude Code skills (installed to ~/.claude/skills/)
  - `init-gsd/` — Project bootstrapper
  - `codex-review/` — Cross-model review via Codex
  - `gsd-codex-verify/` — Combined dual-tool verification gate
- `global/` — Global config templates for Claude and Codex
- `rules/` — .claude/rules/ templates for conditional context injection
- `docs/` — Spec, diagrams, and usage guides
- `install.sh` — One-time installer
- `.planning/` — GSD state (do not manually edit during execution phases)

## Conventions

- Write tests for all new features
- No debug/log statements in production code
- Keep functions small and focused
- Each commit should be atomic and revertable
- Skills must work across Claude Code sessions without re-explaining
- All instruction files must stay under 200 lines for >92% rule adherence

## Workflow

This project uses GSD spec-driven development with dual-tool execution:
1. All planning state lives in `.planning/`
2. Check `.planning/STATE.md` for current workflow position
3. Follow the loop: discuss → plan → execute → verify
4. During execution, split tasks by complexity:
   - Claude Code: complex multi-file changes, architecture, interactive debugging
   - Codex: autonomous tasks, CRUD, tests, scripts, CLI tools, CI/CD
   - Use git worktrees to run both in parallel
5. Cross-review: each tool reviews the OTHER's output
6. Each task produces a separate atomic git commit
