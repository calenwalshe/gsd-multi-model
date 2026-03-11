# gsd-multi-model

Multi-model add-on for [GSD](https://github.com/coleam00/get-shit-done-cc) — adds Claude Code skills for dual-tool (Claude + Codex) workflows.

## Quick Start

```bash
# Install skills (safe default — won't overwrite anything)
npx github:calenwalshe/gsd-multi-model

# Install everything (skills + codex config + rules)
npx github:calenwalshe/gsd-multi-model --all

# Overwrite existing files
npx github:calenwalshe/gsd-multi-model --force
```

Requires [GSD](https://github.com/coleam00/get-shit-done-cc) to be installed first:
```bash
npx get-shit-done-cc@latest --all --global
```

## What It Installs

**Skills** (to `~/.claude/skills/`):
| Skill | Purpose |
|-------|---------|
| `/gsd:drive` | Auto-chain the full GSD loop (discuss → plan → execute → verify) |
| `/init-gsd` | Bootstrap a project with GSD + dual-tool workflow |
| `/codex-review` | Cross-model review (Codex reviews Claude's work) |
| `/gsd-codex-verify` | Combined dual-tool verification gate |
| `/gate-check` | Deterministic quality gates for commits |
| `/observe` | Executor telemetry injection |
| `/gsd-debug` | Observability-driven debugging |
| `/ideate` | Structured brainstorming with project context |
| `/install-skill` | Install skills from any GitHub URL |

**With `--all`** (additionally):
- Codex config (`~/.codex/`)
- Claude Code rules (`~/.claude/rules/`)
- Global workflow files (`~/.claude/`)

## Usage

Once installed, open Claude Code in any project and use the skills:

```bash
claude
# Inside Claude Code:
/init-gsd                  # Bootstrap project
/gsd:new-project           # Deep context gathering → PROJECT.md
/gsd:drive                 # Auto-drive the full workflow
```

### The Workflow Loop

```
discuss → plan → execute (Claude + Codex in parallel) → verify → advance
```

During execution, tasks split by complexity:
- **Claude Code**: complex multi-file changes, architecture, interactive work
- **Codex**: autonomous tasks, CRUD, tests, scripts (runs in parallel worktree)

After execution, each tool reviews the other's work before advancing.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [GSD](https://github.com/coleam00/get-shit-done-cc) base framework
- [Codex CLI](https://github.com/openai/codex) (optional, for dual-tool mode)

## License

MIT
