# Phase 01: The Orchestrator - Context

**Gathered:** 2026-03-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Build `/gsd:drive` as a Claude Code skill that auto-chains discuss -> plan -> execute -> verify -> advance for any given phase or range of phases. Users run `/gsd:drive` and the system drives itself through the full workflow without manual `/clear` + next-command sequences. This replaces the `--auto` flag on individual skills.

</domain>

<decisions>
## Implementation Decisions

### Chaining Strategy
- Build as a SKILL.md (markdown spec for Claude Code), not a standalone daemon
- Sequential Skill() calls within a single invocation: discuss -> plan -> execute -> verify -> transition
- Replaces `--auto` flag entirely — `/gsd:drive` becomes THE way to auto-chain. Remove `--auto` from individual skills.
- Skip completed steps: if CONTEXT.md exists, skip discuss. If PLAN.md exists, skip plan. Only run what's missing.
- Discuss-phase runs in auto-answer mode: Claude picks reasonable defaults for all gray areas, CONTEXT.md created with "Claude's Discretion" for everything
- Auto-advance across phase boundaries — after Phase N verifies, immediately start Phase N+1
- On verification failure: auto-fix and retry up to 2 times before stopping
- Output: banners only between steps (GSD stage banners). No verbose sub-skill output.

### Pause & Resume Behavior
- Pause ONLY when external user action is needed (deploy, configure API key, create account, etc.)
- Never pause for design decisions, technical choices, or verification warnings
- Resume from STATE.md: read current position + check which phase artifacts exist
- Skip-if-artifacts-exist on resume: if the step produced its output file, consider it done
- Append drive log to STATE.md — track step, timestamp, result for each action taken

### Context Reset Mechanism
- Trust Claude Code's built-in context compaction — no proactive checkpointing
- Never mention `/clear` to the user — true autopilot
- Maximize subagent use: every step that can run as a subagent should. Orchestrator only reads STATE.md, determines next action, spawns agent, reads result.
- No per-invocation phase limit — run until all targeted phases complete or unrecoverable error

### Phase Targeting UX
- Bare `/gsd:drive` (no flags): auto-detect next action from STATE.md current position
- `/gsd:drive --phase N`: target specific phase. If dependencies aren't met, auto-drive prerequisite phases first.
- `/gsd:drive --to N`: drive sequentially from current position through phase N
- Completed phases: skip and advance to next incomplete phase (no prompting)
- Sequential execution only — no parallel phase driving even when roadmap allows it
- Final output: milestone-style summary (phases completed, total plans, total commits, deferred ideas) with next milestone prompt

### Claude's Discretion
- Exact state machine logic for determining "next action" from STATE.md + artifacts
- How to detect "external action needed" vs. normal workflow steps
- Drive log format and verbosity in STATE.md
- Error message wording for unrecoverable failures
- How to handle the transition from `--auto` removal (backward compat period or hard cut)

</decisions>

<specifics>
## Specific Ideas

- The `runner/src/state-machine.ts` has a `determineNextAction()` function that maps STATE.md to actions — use its logic as blueprint for the skill's decision tree
- The `runner/src/prompt-expander.ts` shows how to assemble full prompts from workflow files — relevant for how the skill constructs Skill() calls
- Existing `--auto` pattern in discuss-phase.md, plan-phase.md, execute-phase.md shows the Skill() chaining mechanism that `/gsd:drive` will formalize
- `gsd-tools.cjs` already provides `state record-session`, `roadmap get-phase`, `config-get/set` commands — reuse these for state management

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `runner/src/state-machine.ts`: Decision logic (determineNextAction) — blueprint for skill's action routing
- `runner/src/executor-router.ts`: Multi-model task splitting with Codex batch + Claude sequential
- `runner/src/prompt-expander.ts`: Context assembly from workflow markdown files
- `gsd-tools.cjs`: State parsing, roadmap operations, config get/set, commit helpers
- Existing workflow files: discuss-phase.md, plan-phase.md, execute-phase.md, transition.md

### Established Patterns
- Skills are SKILL.md markdown specs with YAML frontmatter (name, description, disable-model-invocation, allowed-tools)
- Auto-chaining uses `Skill(skill="gsd:X", args="N --auto")` calls
- State management via `node gsd-tools.cjs state record-session --stopped-at "..." --resume-file "..."`
- Config flags via `node gsd-tools.cjs config-get/config-set workflow.X`
- Subagent spawning via Agent tool with subagent_type parameter

### Integration Points
- New skill installs to `~/.claude/skills/gsd-drive/SKILL.md` via install.sh / bin/cli.sh
- Reads `.planning/STATE.md` for position, `.planning/ROADMAP.md` for phase graph
- Calls existing workflow skills: gsd:discuss-phase, gsd:plan-phase, gsd:execute-phase, gsd:verify-work
- Writes drive log back to STATE.md

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-the-orchestrator*
*Context gathered: 2026-03-11*
