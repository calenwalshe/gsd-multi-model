# SPEC: GSD + Claude Code + Codex — The Ultimate AI Development Workflow

## Overview

This spec defines a rock-solid development setup that combines three systems:

1. **GSD (Get Shit Done)** — Spec-driven meta-prompting framework that prevents context rot
2. **Claude Code** — Architect + complex coder (interactive, multi-agent, deep context reasoning)
3. **Codex CLI** — Autonomous coder + reviewer (fire & forget, terminal-native, GitHub-integrated)

The result: structured, traceable, high-velocity development where AI tools complement each other and never degrade.

**Bootstrap package:** `~/gsd-bootstrap/` — install once, then `/init-gsd` from inside any Claude session to wire everything up.

---

## 1. Installation & Bootstrap

### One-Time Setup (run once, ever)

```bash
# Install the tools
npm install -g @anthropic-ai/claude-code
npm install -g @openai/codex

# Install the bootstrap package (skills, global configs, GSD)
bash ~/gsd-bootstrap/install.sh
```

This installs three custom skills into `~/.claude/skills/` (available in ALL projects):
- **`/init-gsd`** — Bootstrap any new project from inside Claude
- **`/codex-review`** — Cross-model review with Codex
- **`/gsd-codex-verify`** — Combined dual-tool verification (GSD + Codex)

Plus global configs for both Claude (`~/.claude/CLAUDE.md`) and Codex (`~/.codex/AGENTS.md`, `~/.codex/config.toml`).

### Per-Project Bootstrap (from inside Claude Code)

```bash
mkdir my-new-project && cd my-new-project
claude
# Then inside Claude:
/init-gsd
```

`/init-gsd` creates everything — AGENTS.md, CLAUDE.md, .claude/rules/, git init — all from within the Claude session. No external scripts needed. No re-explaining the workflow. Just `/init-gsd` and go.

### Codex Configuration (`~/.codex/config.toml`)

```toml
model = "gpt-5-codex"
approval_policy = "untrusted"
sandbox_mode = "workspace-write"

# Read Claude/GSD instructions as fallback
project_doc_fallback_filenames = ["CLAUDE.md", "AGENTS.md", "COPILOT.md"]

[profiles.fast]
model = "gpt-5-codex"
approval_policy = "on-request"
```

---

## 2. Project Structure

```
my-project/
├── AGENTS.md                  # Universal instructions (both tools read this)
├── CLAUDE.md                  # Claude-specific (references @AGENTS.md + GSD commands)
├── .planning/                 # GSD state directory (single source of truth)
│   ├── PROJECT.md             # Vision & goals
│   ├── STATE.md               # Current position in workflow
│   ├── ROADMAP.md             # Milestones & phases
│   ├── REQUIREMENTS.md        # Tracked requirements
│   ├── config.json            # GSD settings (mode, depth, model profile)
│   ├── milestones/
│   │   └── m1/
│   │       ├── CONTEXT.md     # Phase decisions
│   │       ├── RESEARCH.md    # Findings
│   │       ├── *-PLAN.md      # Task plans (XML-structured)
│   │       ├── *-SUMMARY.md   # Execution results
│   │       └── VERIFICATION.md # Validation results
│   └── MILESTONES.md          # Completion log
├── src/                       # Your code
└── tests/
```

---

## 3. Shared Instructions Strategy

### `AGENTS.md` (Universal — both Claude Code and Codex read this)

```markdown
# Project: [Name]

## Build & Test
- `npm run build` — build the project
- `npm test` — run tests
- `npm run lint` — lint

## Architecture
[Brief description of directory structure and key modules]

## Conventions
[Coding standards both tools must follow]

## GSD State
- All planning state lives in `.planning/`
- Never modify .planning/ files manually during execution phases
- Check `.planning/STATE.md` for current workflow position
```

### `CLAUDE.md` (Claude-specific)

```markdown
See @AGENTS.md for build commands, architecture, and conventions.

## GSD Workflow
- Use /gsd:status to check current position before starting work
- Use /gsd:discuss-phase → /gsd:plan-phase → /gsd:execute-phase → /gsd:verify-work
- Use subagents: haiku for research, sonnet for implementation, opus for planning/review

## Review Protocol
- After /gsd:verify-work passes, hand off to Codex for cross-model review
- Run /self-review before committing
```

---

## 4. The Workflow — Phase by Phase

### Phase 0: Project Initialization

```bash
# In Claude Code:
/gsd:new-project
# → Creates .planning/ with PROJECT.md, ROADMAP.md, STATE.md, REQUIREMENTS.md

# For existing codebases, map first:
/gsd:map-codebase
# → Analyzes stack, conventions, architecture before planning
```

### Phase 1: Discuss (Claude Code)

```bash
/gsd:discuss-phase
# → Interactive discussion about the current phase
# → Captures decisions in .planning/CONTEXT.md
# → You define WHAT, GSD captures HOW
```

**Why Claude Code here:** Superior at interactive, multi-turn context. Holds your entire vision in context while discussing tradeoffs.

### Phase 2: Plan (Claude Code)

```bash
/gsd:plan-phase
# → Spawns fresh planner agent (clean 200k context)
# → Creates XML-structured PLAN.md with tasks, waves, dependencies
# → Each task has verification steps baked in
```

**Optional cross-validation with Codex:**
```bash
# After Claude generates the plan, have Codex review it
codex "Review .planning/milestones/m1/phase1-PLAN.md for completeness, missing edge cases, and dependency issues"
```

### Phase 3: Execute (Dual-Coder)

Split tasks by complexity — both tools code, each plays to its strengths:

```bash
# CLAUDE CODE handles complex tasks (interactive, multi-file, architecture)
/gsd:execute-phase
# → Spawns fresh executor agent per task (clean 200k context each)
# → Each task = separate atomic git commit
# → Waves enable parallel execution of independent tasks

# CODEX handles autonomous tasks (fire & forget, terminal, well-defined)
# In a parallel worktree:
git worktree add ../task-codex codex-branch
cd ../task-codex
codex --full-auto "Implement tasks X, Y, Z per .planning/milestones/m1/PLAN.md"
# → Runs in sandbox, delivers results for review
# → Great for: CRUD endpoints, tests, scripts, CLI tools, bug fixes, CI/CD
```

**Task splitting guide:**

| Give to Claude Code | Give to Codex |
|---------------------|---------------|
| Multi-file refactoring | CRUD endpoints & API routes |
| Architecture changes | Test writing |
| Complex state management | Scripts & CLI tools |
| Interactive debugging | Bug fixes with clear repro |
| Design-sensitive UI work | CI/CD pipelines |
| Anything needing your input | Anything well-defined & autonomous |

### Phase 4: Verify (Dual-Tool)

```bash
# Option A: Combined (recommended) — runs both in sequence
/gsd-codex-verify
# → Runs GSD verifier agent first (structural check against specs)
# → Then runs Codex cross-model review automatically
# → Produces combined PASS/FAIL report

# Option B: Separate steps
/gsd:verify-work              # GSD structural verification
/codex-review                 # Then Codex cross-model review
/codex-review security        # Or with a specific focus area
```

**The cross-review pattern:** Each tool reviews what the OTHER built. Claude verifies Codex's autonomous work against specs. Codex reviews Claude's complex changes for blind spots. Different models catch different bugs. `/gsd-codex-verify` combines both into one command.

### Phase 5: Advance

```bash
# If verification passes:
/gsd:complete-milestone   # or advance to next phase

# If issues found:
# Fix in Claude Code, re-verify, then Codex review again
```

---

## 5. The Division of Labor

| Task | Primary Tool | Why |
|------|-------------|-----|
| Architecture & planning | Claude Code + GSD | Interactive reasoning, multi-turn context |
| Discussion & requirements | Claude Code + GSD | Decision capture, tradeoff analysis |
| Complex multi-file changes | Claude Code | Deep context, interactive steering |
| Autonomous well-defined tasks | Codex | Fire & forget, sandbox execution, cheaper |
| Terminal/CLI/script tasks | Codex | Leads Terminal-Bench by 12 points |
| CRUD, endpoints, bug fixes | Codex | Well-defined = autonomous-friendly |
| Test writing | Codex or split | Codex writes tests, Claude implements (or vice versa) |
| CI/CD & GitHub workflows | Codex | GitHub-native integration |
| PR review | Codex | Auto-review catches subtle bugs |
| Exploration / research | Either (switch if stuck) | Different models find different solutions |
| Final verification | Both (cross-review) | Each reviews the OTHER's work |

---

## 6. Parallel Execution with Worktrees

The real velocity multiplier — both tools coding simultaneously on different tasks:

```bash
# Create isolated worktrees from the GSD plan
git worktree add ../task-complex complex-branch
git worktree add ../task-auto auto-branch

# Terminal 1: Claude handles complex architecture work (interactive)
cd ../task-complex && claude
# → /gsd:execute-phase on the complex tasks

# Terminal 2: Codex handles well-defined tasks (autonomous)
cd ../task-auto && codex --full-auto \
  "Implement the API endpoints and tests per .planning/milestones/m1/PLAN.md tasks 3-6"
# → Runs in sandbox, you review when done

# When both finish, merge worktrees and cross-review:
# Claude reviews Codex's work, Codex reviews Claude's work
```

**Multiple Codex agents in parallel:**
```bash
# Codex is cheap ($20/mo) — run multiple autonomous tasks at once
git worktree add ../task-tests test-branch
git worktree add ../task-api api-branch
git worktree add ../task-ci ci-branch

cd ../task-tests && codex --full-auto "Write tests for auth module" &
cd ../task-api && codex --full-auto "Implement CRUD endpoints" &
cd ../task-ci && codex --full-auto "Set up GitHub Actions CI pipeline" &
# → All three run simultaneously in sandboxes
```

---

## 7. GSD Configuration (`.planning/config.json`)

```json
{
  "mode": "interactive",
  "depth": "standard",
  "model_profile": "quality",
  "workflow": {
    "research": true,
    "plan_check": true,
    "verifier": true
  },
  "parallelization": {
    "enabled": true
  },
  "git": {
    "branching_strategy": "phase",
    "branch_templates": {
      "phase": "gsd/m{milestone}-p{phase}",
      "milestone": "gsd/milestone-{milestone}"
    }
  }
}
```

### Model Profiles

| Profile | Planner | Executor | Verifier | Research |
|---------|---------|----------|----------|----------|
| `quality` | Opus | Sonnet | Opus | Haiku |
| `balanced` | Sonnet | Sonnet | Sonnet | Haiku |
| `budget` | Sonnet | Haiku | Sonnet | Haiku |

---

## 8. Anti-Context-Rot Strategy

The core innovation: **no single agent session ever degrades**.

| Problem | GSD Solution | Dual-Tool Bonus |
|---------|-------------|-----------------|
| Context fills up | Fresh 200k subagent per task | Switch to Codex for fresh perspective |
| AI "forgets" requirements | .planning/ files are source of truth | Both tools read same state files |
| Quality degrades over time | Atomic commits per task, revertable | Cross-model review catches drift |
| Lost continuity between sessions | STATE.md tracks exact position | AGENTS.md keeps both tools aligned |

---

## 9. Daily Workflow Cheat Sheet

```
Morning:
  1. claude → /gsd:status           # Where am I?
  2. /gsd:discuss-phase              # Align on today's work
  3. /gsd:plan-phase                 # Generate tasks, tag as complex vs autonomous

Execute (parallel):
  4. /gsd:execute-phase              # Claude: complex tasks (interactive)
  5. codex --full-auto "tasks..."    # Codex: autonomous tasks (fire & forget)
     (in separate worktree)          # Can run multiple Codex agents at once

Verify (cross-review):
  6. /gsd-codex-verify               # Claude reviews Codex's work
                                     # Codex reviews Claude's work
                                     # Combined PASS/FAIL report

Close:
  7. /gsd:complete-milestone         # Archive & advance
  8. git push                        # Ship it
```

---

## 10. Key Commands Reference

| Command | Tool | Purpose |
|---------|------|---------|
| `/gsd:new-project` | Claude | Initialize GSD project |
| `/gsd:map-codebase` | Claude | Analyze existing codebase |
| `/gsd:discuss-phase` | Claude | Capture phase decisions |
| `/gsd:plan-phase` | Claude | Generate task plan |
| `/gsd:execute-phase` | Claude | Run tasks with fresh agents |
| `/gsd:verify-work` | Claude | Validate against requirements |
| `/gsd:status` | Claude | Check current position |
| `/gsd:progress` | Claude | View overall progress |
| `/gsd:audit-milestone` | Claude | Pre-completion audit |
| `/gsd:complete-milestone` | Claude | Archive & advance |
| `/init-gsd` | Claude | Bootstrap new project with dual-tool workflow |
| `/codex-review` | Claude→Codex | Cross-model code review via Codex |
| `/codex-review security` | Claude→Codex | Focused cross-model review |
| `/gsd-codex-verify` | Both | Combined GSD + Codex verification gate |
| `codex --full-auto` | Codex | Autonomous execution (sandboxed) |

---

## 11. When Things Go Wrong

| Situation | Action |
|-----------|--------|
| Claude stuck on a problem | Switch to `codex` — different model, different solution |
| Codex output is off | Switch back to Claude Code with GSD context |
| Context feels degraded | `/gsd:execute-phase` spawns fresh agent automatically |
| Lost track of progress | `/gsd:status` reads STATE.md |
| Need to revert bad work | Each GSD task = atomic commit → `git revert` |
| Phase plan was wrong | `/gsd:plan-phase` again with new context |
| Both tools disagree | Trust the one whose output passes `/gsd:verify-work` |

---

## Summary

**GSD gives you structure** — spec-driven planning, fresh contexts, atomic commits, and traceable state.

**Claude Code is your architect + complex coder** — interactive reasoning, multi-agent orchestration, deep context. Handles the hard stuff where you need to be in the loop.

**Codex is your autonomous coder + reviewer** — fire and forget, sandbox execution, terminal-native, cheap. Handles well-defined tasks at scale while you focus on the complex work with Claude.

**The cross-review pattern is the force multiplier** — each tool reviews the other's output. Different models catch different blind spots. No single point of failure.

Together: Claude plans and handles complexity, Codex executes autonomously in parallel, both verify each other's work. No context rot. No lost state. Every task traceable. Ship with confidence.
