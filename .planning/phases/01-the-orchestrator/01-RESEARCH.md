# Phase 01: The Orchestrator - Research

**Researched:** 2026-03-11
**Domain:** Claude Code skill orchestration, state machine design, subagent chaining
**Confidence:** HIGH

## Summary

This phase builds `/gsd:drive` as a SKILL.md (markdown spec) that reads STATE.md and ROADMAP.md to determine the next workflow action, then dispatches to existing skills (discuss-phase, plan-phase, execute-phase, verify-work, transition) via Skill() calls. The existing codebase already contains the complete decision logic in `runner/src/state-machine.ts` and the prompt expansion in `runner/src/prompt-expander.ts` -- the skill needs to port this logic into a markdown-native format that Claude Code interprets directly.

The existing `--auto` flag mechanism in discuss-phase.md, plan-phase.md, and execute-phase.md already implements chaining via `Skill()` calls and `workflow._auto_chain_active` config flags. `/gsd:drive` formalizes and replaces this pattern with a single entry point that owns the full loop, using subagent spawning (Agent tool) per step to maximize context isolation.

**Primary recommendation:** Build a single `skills/gsd-drive/SKILL.md` that implements a state-machine loop: read STATE.md -> determine next action -> spawn subagent for that action -> read result -> repeat. Replace all `--auto` flags in existing workflow files with a check for "am I being called by /gsd:drive" (or simply remove them).

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Chaining Strategy:**
- Build as a SKILL.md (markdown spec for Claude Code), not a standalone daemon
- Sequential Skill() calls within a single invocation: discuss -> plan -> execute -> verify -> transition
- Replaces `--auto` flag entirely -- `/gsd:drive` becomes THE way to auto-chain. Remove `--auto` from individual skills.
- Skip completed steps: if CONTEXT.md exists, skip discuss. If PLAN.md exists, skip plan. Only run what's missing.
- Discuss-phase runs in auto-answer mode: Claude picks reasonable defaults for all gray areas, CONTEXT.md created with "Claude's Discretion" for everything
- Auto-advance across phase boundaries -- after Phase N verifies, immediately start Phase N+1
- On verification failure: auto-fix and retry up to 2 times before stopping
- Output: banners only between steps (GSD stage banners). No verbose sub-skill output.

**Pause & Resume Behavior:**
- Pause ONLY when external user action is needed (deploy, configure API key, create account, etc.)
- Never pause for design decisions, technical choices, or verification warnings
- Resume from STATE.md: read current position + check which phase artifacts exist
- Skip-if-artifacts-exist on resume: if the step produced its output file, consider it done
- Append drive log to STATE.md -- track step, timestamp, result for each action taken

**Context Reset Mechanism:**
- Trust Claude Code's built-in context compaction -- no proactive checkpointing
- Never mention `/clear` to the user -- true autopilot
- Maximize subagent use: every step that can run as a subagent should. Orchestrator only reads STATE.md, determines next action, spawns agent, reads result.
- No per-invocation phase limit -- run until all targeted phases complete or unrecoverable error

**Phase Targeting UX:**
- Bare `/gsd:drive` (no flags): auto-detect next action from STATE.md current position
- `/gsd:drive --phase N`: target specific phase. If dependencies aren't met, auto-drive prerequisite phases first.
- `/gsd:drive --to N`: drive sequentially from current position through phase N
- Completed phases: skip and advance to next incomplete phase (no prompting)
- Sequential execution only -- no parallel phase driving even when roadmap allows it
- Final output: milestone-style summary (phases completed, total plans, total commits, deferred ideas) with next milestone prompt

### Claude's Discretion

- Exact state machine logic for determining "next action" from STATE.md + artifacts
- How to detect "external action needed" vs. normal workflow steps
- Drive log format and verbosity in STATE.md
- Error message wording for unrecoverable failures
- How to handle the transition from `--auto` removal (backward compat period or hard cut)

### Deferred Ideas (OUT OF SCOPE)

None -- discussion stayed within phase scope

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ORCH-01 | `/gsd:drive` auto-chains discuss -> plan -> execute -> verify -> advance for a given phase | State machine logic from `runner/src/state-machine.ts`, Skill() chaining from existing `--auto` pattern, artifact existence checks |
| ORCH-02 | Orchestrator handles context resets between phases internally (no manual `/clear`) | Subagent spawning via Agent tool provides natural context isolation; trust Claude Code compaction |
| ORCH-03 | Orchestrator pauses only on genuine decision points (ambiguous requirements, verification failures, user input needed) | Detect "external action needed" via keyword scanning in skill output or explicit pause markers |
| ORCH-04 | Orchestrator reads STATE.md to resume from any position after interruption | `state-parser.ts` parsing logic + artifact existence checks for skip-if-done |
| ORCH-05 | Orchestrator supports `--phase N` to target a specific phase and `--to N` to drive through a range | ROADMAP.md parsing for dependency checking, phase iteration logic |

</phase_requirements>

## Standard Stack

### Core

| Component | Location | Purpose | Why Standard |
|-----------|----------|---------|--------------|
| SKILL.md | `skills/gsd-drive/SKILL.md` | Main orchestrator skill spec | All GSD skills are SKILL.md markdown -- consistent pattern |
| gsd-tools.cjs | `~/.claude/get-shit-done/bin/gsd-tools.cjs` | State parsing, config, roadmap ops | Already handles all state management; avoid reimplementing |
| Existing workflow skills | `~/.claude/commands/gsd/*.md` | Individual step implementations | discuss-phase, plan-phase, execute-phase, verify-work, transition already work |

### Supporting

| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `state-parser.ts` logic | Parse STATE.md for phase/plan position | Blueprint for SKILL.md decision tree -- port logic to markdown instructions |
| `state-machine.ts` logic | Determine next action from state | Blueprint for action routing -- skill reimplements as conditional instructions |
| `config-get`/`config-set` | Read/write workflow flags | Track drive state, auto-chain flags |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SKILL.md (markdown) | TypeScript runner daemon (`runner/src/index.ts`) | Runner exists but requires Agent SDK, external process, Docker. SKILL.md works within Claude Code session model -- locked decision. |
| Skill() calls | Agent tool with subagent | Skill() keeps flat nesting (no deep agent trees). Agent tool provides context isolation but adds nesting depth. Use Skill() for step dispatch. |
| Remove --auto entirely | Keep --auto as fallback | Hard cut is cleaner. --auto callers should use /gsd:drive instead. Remove --auto from workflow files. |

## Architecture Patterns

### Recommended Project Structure

```
skills/gsd-drive/
    SKILL.md           # Main orchestrator skill (~200 lines)
```

Changes to existing files:
```
skills/init-gsd/SKILL.md         # Add gsd-drive to install list
bin/cli.sh                        # Add gsd-drive skill copy
~/.claude/commands/gsd/drive.md   # Command entry point (thin, delegates to skill)

# Modified workflow files (remove --auto sections):
~/.claude/get-shit-done/workflows/discuss-phase.md
~/.claude/get-shit-done/workflows/plan-phase.md
~/.claude/get-shit-done/workflows/execute-phase.md
```

### Pattern 1: State Machine as Markdown Instructions

**What:** The SKILL.md contains a decision tree expressed as conditional instructions that Claude Code follows. Not code -- structured prose that maps state to actions.

**When to use:** When the orchestration logic is simple enough to express as "if X then do Y" rules.

**Example:**
```markdown
## Step 3: Determine Next Action

Read STATE.md and parse current position:
- Extract phase number from "Phase: XX of YY"
- Extract plan status from "Plan: X of Y"
- Extract status line

Check artifacts in the current phase directory:

1. **No CONTEXT.md exists** -> Run discuss-phase
2. **CONTEXT.md exists, no RESEARCH.md** -> Run research-phase (if config.research enabled)
3. **CONTEXT.md exists, no PLAN.md files** -> Run plan-phase
4. **PLAN.md exists, not all SUMMARY.md files** -> Run execute-phase
5. **All SUMMARY.md files exist** -> Run verify-work
6. **UAT.md exists with PASS** -> Run transition
7. **UAT.md exists with FAIL + fix plans** -> Run execute-phase --gaps-only, then re-verify
```

### Pattern 2: Subagent-per-Step for Context Isolation

**What:** Each workflow step (discuss, plan, execute, verify) runs as a Skill() call. The orchestrator stays lean -- it only reads STATE.md, determines the action, dispatches, and reads the result.

**When to use:** Always. This is the locked decision for context management.

**Example:**
```markdown
## Step 4: Dispatch Action

Based on the determined action, invoke the appropriate skill:

**For discuss:**
Skill(skill="gsd:discuss-phase", args="${PHASE} --auto")

**For plan:**
Skill(skill="gsd:plan-phase", args="${PHASE} --auto --skip-verify")

**For execute:**
Skill(skill="gsd:execute-phase", args="${PHASE}")

**For verify:**
Skill(skill="gsd:verify-work", args="${PHASE}")
```

### Pattern 3: Artifact-Based Skip Detection

**What:** Before running any step, check if its output artifact already exists. If so, skip to the next step.

**When to use:** On every loop iteration, especially for resume-after-interruption.

**How it works:**
```
Phase directory: .planning/phases/XX-name/
  XX-CONTEXT.md  -> discuss complete
  XX-RESEARCH.md -> research complete
  XX-*-PLAN.md   -> plan complete (at least one plan file)
  XX-*-SUMMARY.md -> execution complete (count must match PLAN count)
  XX-UAT.md      -> verification complete (check PASS/FAIL status)
```

### Pattern 4: Drive Log in STATE.md

**What:** Append timestamped entries to a "Drive Log" section in STATE.md so resume can reconstruct what happened.

**Example format:**
```markdown
## Drive Log

| Timestamp | Phase | Step | Result |
|-----------|-------|------|--------|
| 2026-03-11T08:00:00Z | 01 | discuss | complete |
| 2026-03-11T08:05:00Z | 01 | plan | complete (2 plans) |
| 2026-03-11T08:30:00Z | 01 | execute | complete |
| 2026-03-11T08:45:00Z | 01 | verify | PASS |
| 2026-03-11T08:46:00Z | 01 | transition | complete |
```

### Anti-Patterns to Avoid

- **Deep agent nesting:** Never use Agent(Task()) inside a Skill() call. Keep nesting flat. Skill() calls from the orchestrator, subagents inside skills if needed -- but never the orchestrator spawning agents that spawn agents that spawn agents. This causes Claude Code runtime freezes (#686 referenced in discuss-phase.md).
- **In-memory state tracking:** Never track progress in variables across iterations. Always re-read STATE.md and artifacts from disk. The orchestrator must be stateless between steps.
- **Proactive checkpointing:** Don't run /gsd:pause-work between steps. Trust Claude Code's compaction. The runner daemon does checkpointing, but the skill doesn't need it.
- **Verbose output between steps:** The orchestrator should print banners only. No progress bars, no step-by-step narration. Users see the final summary.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| STATE.md parsing | Custom regex parsing in SKILL.md | `node gsd-tools.cjs state` | Already parses frontmatter + position + status correctly |
| Phase directory resolution | Manual path construction | `node gsd-tools.cjs init phase-op ${PHASE}` | Handles padded numbers, slug resolution, existence checks |
| Roadmap parsing | Regex over ROADMAP.md | `node gsd-tools.cjs roadmap analyze` | Returns structured JSON of all phases with completion status |
| Config read/write | File editing | `node gsd-tools.cjs config-get/config-set` | Thread-safe, handles missing keys |
| Phase completion | Manual ROADMAP.md + STATE.md edits | `node gsd-tools.cjs phase complete ${PHASE}` | Updates roadmap checkbox, state position, progress table |
| Timestamp generation | Inline date commands | `node gsd-tools.cjs current-timestamp` | Consistent ISO format |

**Key insight:** gsd-tools.cjs is the canonical state management layer. The SKILL.md orchestrator should call it for ALL state reads and writes -- never parse or edit STATE.md directly.

## Common Pitfalls

### Pitfall 1: Skill() vs Agent Tool Confusion

**What goes wrong:** Using Agent tool (subagent spawning) when Skill() (flat skill invocation) is needed, or vice versa.
**Why it happens:** Both dispatch work to Claude, but Skill() runs in the current context while Agent creates a nested context.
**How to avoid:** Use Skill() for workflow step dispatch. The existing discuss-phase.md explicitly uses Skill() (line 623) and documents why: "keeps the auto-advance chain flat."
**Warning signs:** Runtime freezes, infinite nesting, context budget exhaustion.

### Pitfall 2: --auto Flag Removal Breaking Manual Usage

**What goes wrong:** Removing --auto from workflow files breaks the existing manual chaining that some users rely on.
**Why it happens:** --auto is currently the mechanism for both /gsd:drive-style automation AND transition.md's auto-advance between phases.
**How to avoid:** Two-phase approach: (1) Add /gsd:drive as the primary entry point, (2) Remove --auto sections from workflow files only after /gsd:drive is working. Keep transition.md's YOLO mode Skill() calls intact but route them through /gsd:drive logic. Alternatively, do a hard cut since the user locked "remove --auto from individual skills."
**Warning signs:** transition.md's "yolo" mode auto-advance stops working after --auto removal.

### Pitfall 3: Artifact Existence != Step Success

**What goes wrong:** Assuming a file exists means the step completed successfully. A CONTEXT.md might exist from a previous failed attempt.
**Why it happens:** Skip-if-artifacts-exist is a good heuristic but not perfect.
**How to avoid:** For verification (UAT.md), check content not just existence -- look for PASS/FAIL verdict. For other artifacts, existence is sufficient (locked decision: "if the step produced its output file, consider it done").
**Warning signs:** Stuck loops where a step keeps getting skipped but downstream steps fail.

### Pitfall 4: Phase Dependency Resolution for --phase N

**What goes wrong:** User runs `/gsd:drive --phase 3` but phases 1-2 aren't complete. Orchestrator either errors out or runs phase 3 on incomplete foundations.
**Why it happens:** --phase N implies "go directly to N" but dependencies must be met.
**How to avoid:** Before targeting phase N, check ROADMAP.md for dependency chain. If prerequisites incomplete, auto-drive them first (locked decision). Use `gsd-tools.cjs roadmap analyze` to get completion status of all phases.
**Warning signs:** Missing CONTEXT.md/PLAN.md for earlier phases when trying to execute a later one.

### Pitfall 5: Verification Retry Loop

**What goes wrong:** Verification fails, fix plans are created, executed, but re-verification fails again -- infinite loop.
**Why it happens:** The "auto-fix and retry up to 2 times" limit isn't enforced, or the fix doesn't address the actual issue.
**How to avoid:** Track retry count in the drive log. After 2 failed verification retries, stop with actionable error message. Use a counter variable within the SKILL.md loop, not persistent state.
**Warning signs:** Same UAT.md failure appearing 3+ times in drive log.

### Pitfall 6: SKILL.md Length Exceeding 200 Lines

**What goes wrong:** The orchestrator skill grows beyond the 200-line limit for >92% rule adherence.
**Why it happens:** Complex state machine + argument parsing + error handling + banners can be verbose.
**How to avoid:** Keep the SKILL.md focused on the decision tree and dispatch. Move detailed instructions (banner formatting, error messages) into a referenced workflow file at `~/.claude/get-shit-done/workflows/drive.md`. The SKILL.md delegates via `@/path/to/workflow.md` reference.
**Warning signs:** SKILL.md approaching 150+ lines during drafting.

## Code Examples

### Determining Next Action (from state-machine.ts -- blueprint)

```typescript
// Source: runner/src/state-machine.ts (lines 18-92)
// This is the REFERENCE logic to port into SKILL.md instructions

export function determineNextAction(projectDir: string): GsdAction {
  // 0. Check for resume file
  if (existsSync(continueHerePath)) return { type: 'resume' };

  // 1. No PROJECT.md -> init
  if (!existsSync(projectPath)) return { type: 'init-project', brief };

  // 2. Parse state
  const state = parseStateFile(stateContent);

  // 3. All phases complete -> done
  if (roadmap.every(p => p.complete)) return { type: 'done' };

  // 4. Route based on status
  if (state.plansInPhase === 0) return { type: 'plan', phase };
  if (state.plansComplete < state.plansInPhase) return { type: 'execute', phase };
  if (state.plansComplete === state.plansInPhase) return { type: 'verify', phase };
}
```

### Existing Skill() Chaining (from discuss-phase.md)

```markdown
<!-- Source: ~/.claude/get-shit-done/workflows/discuss-phase.md (line 621-623) -->
Launch plan-phase using the Skill tool to avoid nested Task sessions:

Skill(skill="gsd:plan-phase", args="${PHASE} --auto")
```

### gsd-tools State Commands

```bash
# Get full state + config as JSON
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" state

# Get phase info
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" init phase-op ${PHASE}

# Analyze roadmap (all phases with completion status)
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" roadmap analyze

# Read/write config
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-get workflow._auto_chain_active
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set workflow._auto_chain_active true

# Mark phase complete
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" phase complete ${PHASE}

# Record session for resume
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" state record-session --stopped-at "..." --resume-file "..."

# Generate timestamp
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" current-timestamp
```

### SKILL.md Frontmatter Pattern

```yaml
---
name: gsd-drive
description: Auto-drive the full GSD workflow for one or more phases
argument-hint: "[--phase N] [--to N]"
allowed-tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - Task
---
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual `/clear` + next command | `--auto` flag on individual skills | v1.1 (2026-03-05) | Partial automation -- user still initiates chain |
| `--auto` flag chaining | `/gsd:drive` single entry point | v2.0 (this phase) | Full autopilot -- one command drives everything |
| Runner daemon (index.ts) | SKILL.md within Claude Code session | v2.0 (this phase) | No external process needed -- works in any Claude Code session |

**Key context:** The runner daemon (`runner/src/`) was built for unattended execution (Docker, Agent SDK, Telegram notifications). `/gsd:drive` is the interactive counterpart -- same logic, but inside the user's Claude Code session.

## Open Questions

1. **Skill() return value detection**
   - What we know: Skill() calls invoke a skill and return. The existing --auto pattern checks for chain flags after Skill() returns.
   - What's unclear: Can the orchestrator detect whether a Skill() call succeeded or failed? The discuss-phase.md auto_advance step handles "PHASE COMPLETE", "PLANNING COMPLETE", "GAPS FOUND" return states -- how are these communicated back?
   - Recommendation: After each Skill() call, re-read STATE.md and artifacts to determine outcome. Don't rely on Skill() return values -- use disk state as the source of truth.

2. **transition.md integration**
   - What we know: transition.md handles phase completion (ROADMAP update, PROJECT.md evolution, STATE.md advancement). It currently has its own auto-advance routing in yolo mode.
   - What's unclear: Should /gsd:drive call transition.md as a separate step, or should it call `gsd-tools.cjs phase complete` directly?
   - Recommendation: Call transition.md as a Skill() call since it handles PROJECT.md evolution (which requires reading summaries and making judgment calls). Let transition.md do its full flow, then the orchestrator reads the updated STATE.md.

3. **Backward compatibility period for --auto removal**
   - What we know: User locked "remove --auto from individual skills."
   - What's unclear: Whether to remove --auto in this phase or leave it as no-op for one release.
   - Recommendation: Hard cut. Remove --auto sections from workflow files in this phase. Anyone using --auto should switch to /gsd:drive. This is a major version bump (v2.0) so breaking changes are expected.

## Validation Architecture

> `workflow.nyquist_validation` is not explicitly set to false in config.json, so validation architecture is included.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash + manual verification |
| Config file | none -- SKILL.md is a markdown spec, not executable code |
| Quick run command | Manual: run `/gsd:drive` in a test project |
| Full suite command | `bash test-install.sh` (verifies skill files installed correctly) |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ORCH-01 | /gsd:drive chains discuss->plan->execute->verify->advance | integration (manual) | Run `/gsd:drive` on a fresh phase | No -- Wave 0 |
| ORCH-02 | Context resets happen internally | smoke (manual) | Verify no `/clear` instructions in output | No -- Wave 0 |
| ORCH-03 | Pauses only on genuine decision points | smoke (manual) | Run drive, confirm no unnecessary pauses | No -- Wave 0 |
| ORCH-04 | Resume from STATE.md after interruption | integration (manual) | Interrupt drive mid-phase, re-run, verify resume | No -- Wave 0 |
| ORCH-05 | `--phase N` and `--to N` flags work | unit (bash) | `bash bin/test-drive-args.sh` | No -- Wave 0 |

### Sampling Rate

- **Per task commit:** `bash test-install.sh` (verify files installed)
- **Per wave merge:** Manual /gsd:drive test on a scratch project
- **Phase gate:** Full /gsd:drive run through at least one phase lifecycle

### Wave 0 Gaps

- [ ] `bin/test-drive-args.sh` -- unit test for argument parsing (--phase N, --to N, bare invocation)
- [ ] `test-install.sh` update -- add gsd-drive skill to installation verification
- [ ] Scratch test project -- a minimal .planning/ setup for integration testing

## Sources

### Primary (HIGH confidence)

- `runner/src/state-machine.ts` -- Decision logic blueprint, verified by reading source
- `runner/src/state-parser.ts` -- STATE.md parsing patterns, verified by reading source
- `runner/src/prompt-expander.ts` -- Prompt construction patterns, verified by reading source
- `runner/src/index.ts` -- Main loop pattern, verified by reading source
- `runner/src/executor-router.ts` -- Task routing patterns, verified by reading source
- `~/.claude/get-shit-done/workflows/discuss-phase.md` -- Skill() chaining pattern, --auto mechanism
- `~/.claude/get-shit-done/workflows/plan-phase.md` -- --auto chain propagation
- `~/.claude/get-shit-done/workflows/execute-phase.md` -- --auto chain propagation
- `~/.claude/get-shit-done/workflows/transition.md` -- Phase completion and auto-advance routing
- `~/.claude/commands/gsd/*.md` -- All 32 GSD command entry points
- `skills/init-gsd/SKILL.md` -- Reference SKILL.md pattern (frontmatter, step structure, 552 lines but complex)

### Secondary (MEDIUM confidence)

- CONTEXT.md decisions on Skill() vs Agent tool nesting -- based on discuss-phase.md #686 reference about runtime freezes

### Tertiary (LOW confidence)

- Skill() return value behavior -- inferred from existing patterns, not verified against Claude Code SDK docs

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all components are existing codebase files, verified by reading source
- Architecture: HIGH -- patterns extracted from working code (--auto mechanism, state machine, Skill() calls)
- Pitfalls: HIGH -- identified from existing code comments (#686 nesting issue) and architectural analysis
- Open questions: MEDIUM -- Skill() return values and transition.md integration need validation during implementation

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable -- internal tooling, no external dependency churn)
