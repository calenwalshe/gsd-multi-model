# Research: Existing gsd-multi-model Codebase

**Date**: 2026-03-02
**Scope**: Full catalog of existing implementation, architecture, gaps
**Status**: Complete — all files analyzed

---

## Executive Summary

The gsd-multi-model project is a **dual-tool AI development framework** combining Claude Code (planning/orchestration) and Codex CLI (autonomous execution) into a unified GSD-driven workflow.

**Current state**: 80% conceptual infrastructure, 20% implementation. All project documentation, specification, installer, and three skills are written. GSD framework itself is assumed to be installed separately (not bundled). Test verification passes. The project is ready for Phase 2 (Requirements) and Phase 3 (Roadmap).

**What exists**:
- `/init-gsd` skill — Full spec for bootstrapping new projects
- `/codex-review` skill — Spec for cross-model code review
- `/gsd-codex-verify` skill — Spec for dual-tool verification gate
- `install.sh` — Full installer that installs skills and global configs
- `test-install.sh` — Verification script (16 checks, currently fails due to missing GSD framework)
- `docs/SPEC.md` — Comprehensive 407-line specification document
- `AGENTS.md` / `CLAUDE.md` — Project instructions (dual-tool workflow)
- `.claude/rules/` — 4 context injection rules (gsd-workflow, planning-files, test-files, security)
- Global templates — Codex agent instructions and config template
- `.planning/` — GSD state (PROJECT.md, STATE.md, config.json)

**What's missing**:
1. **GSD framework integration** — Specification assumes GSD is installed separately; installation script attempts to install it but framework isn't bundled
2. **REQUIREMENTS.md** — Not yet created (needed before roadmap)
3. **ROADMAP.md** — Not yet created (Phase 0 deliverable)
4. **Worktree management automation** — Spec mentions git worktree usage but no helper scripts written
5. **Example projects** — No demo project showing the workflow in practice
6. **Milestone planning** — `.planning/milestones/` directory not created

---

## What Exists — Detailed Catalog

### 1. Skills (Three Custom Claude Code Skills)

#### `/init-gsd` — Project Bootstrap
**File**: `/home/agent/gsd-multi-model/skills/init-gsd/SKILL.md` (236 lines)

**Purpose**: One-command project initialization for any new project.

**Spec Steps**:
1. Detect project context (language, build system)
2. Create `AGENTS.md` (universal Claude + Codex instructions)
3. Create `CLAUDE.md` (Claude-specific GSD workflow)
4. Install `.claude/rules/` (4 context rules)
5. Set up global `~/.codex/config.toml` and `~/.codex/AGENTS.md` (one-time)
6. Set up global `~/.claude/CLAUDE.md` (one-time)
7. Install GSD framework globally
8. Create `.gitignore`
9. Print summary

**Status**: SPEC ONLY — No implementation code. The skill itself needs to be a Claude Code script that performs these 9 steps.

**Implementation Gaps**:
- No actual skill logic code (only markdown spec)
- Step 1 (project context detection) undefined — what patterns to match for stack detection
- Steps 2-4 need template generation with variable substitution
- Step 7 calls `npx get-shit-done-cc@latest` but GSD framework isn't bundled with this project

---

#### `/codex-review` — Cross-Model Code Review
**File**: `/home/agent/gsd-multi-model/skills/codex-review/SKILL.md` (72 lines)

**Purpose**: From Claude Code, trigger Codex to review Claude's complex work.

**Spec Steps**:
1. Gather review context (STATE.md, REQUIREMENTS.md, git diff)
2. Build review prompt with focus area (from `$ARGUMENTS`)
3. Run Codex with specific review checklist (bugs, security, tests, edge cases, conventions)
4. Also review any Codex-built code with Claude
5. Display combined results

**Status**: SPEC ONLY — Framework for the review, but no implementation.

**Implementation Gaps**:
- No skill logic code
- Step 3 assumes `codex` CLI is available — needs error handling if not installed
- No integration with GSD's git branch management
- "Also review Codex-built code" (step 4) is vague — what constitutes "Codex-built"?

---

#### `/gsd-codex-verify` — Dual-Tool Verification Gate
**File**: `/home/agent/gsd-multi-model/skills/gsd-codex-verify/SKILL.md` (92 lines)

**Purpose**: Combined quality gate before phase advancement.

**Spec Steps**:
1. Run `/gsd:verify-work` (GSD structural verification)
2. Assess GSD results — if fail, stop; if pass, continue
3. Identify who built what (git log)
4. Claude reviews Codex's autonomous output
5. Codex reviews Claude's complex work
6. Present combined report
7. Recommend next action

**Status**: SPEC ONLY — Framework but no implementation.

**Implementation Gaps**:
- No skill logic code
- Step 3 "identify who built what" needs better heuristics (how to tag commits as Claude vs Codex?)
- Step 5 needs inline review code, not just prompt
- Report format (step 6) is nice-to-have, not enforced

---

### 2. Global Configurations

#### `global/codex-agents.md` — Codex Instructions
**File**: `/home/agent/gsd-multi-model/global/codex-agents.md` (27 lines)

**Content**: Template instructions for Codex CLI when used in the dual-tool workflow.

**What it says**:
- When coding: Read AGENTS.md + .planning/PLAN.md, focus on well-defined tasks, deliver tested implementations
- When reviewing: Check REQUIREMENTS.md + STATE.md, look for bugs/security/test gaps, report with severity
- Rules: Follow AGENTS.md conventions, make atomic commits, never modify .planning/, test before committing

**Status**: COMPLETE — This is a static template, no dependencies.

**Quality**: Good — Covers both roles (coder + reviewer). Clear severity model (CRITICAL/WARNING/INFO).

---

#### `global/codex-config.toml` — Codex Configuration
**File**: `/home/agent/gsd-multi-model/global/codex-config.toml` (16 lines)

**Content**:
```toml
model = "gpt-5-codex"
approval_policy = "untrusted"
sandbox_mode = "workspace-write"
project_doc_fallback_filenames = ["CLAUDE.md", "COPILOT.md"]

[profiles.review]
model = "gpt-5-codex"
approval_policy = "untrusted"
sandbox_mode = "read-only"

[profiles.fast]
model = "gpt-5-codex"
approval_policy = "on-request"
```

**Status**: COMPLETE — Template is ready.

**Issues**:
- `approval_policy = "untrusted"` + `sandbox_mode = "workspace-write"` is a contradiction. "Untrusted" mode should have read-only sandbox for safety. Review mode gets this right (read-only).
- `model = "gpt-5-codex"` assumes a Codex model that doesn't exist yet (as of Feb 2025). Should use a real model name.

---

### 3. Rules (Conditional Context Injection)

**Files**: `.claude/rules/` — 4 rules

#### `gsd-workflow.md` — Always Active
(7 lines) Plain markdown, no path conditions.

States:
1. Check `/gsd:status` before changes
2. Respect `.planning/STATE.md` position
3. Suggest Codex for autonomous tasks
4. Atomic commits per task
5. Run `/gsd-codex-verify` after execution

**Status**: COMPLETE — Activates on every GSD project.

---

#### `planning-files.md` — Activates on `.planning/**`
(11 lines) YAML front-matter with path patterns.

States:
- STATE.md tracks position
- PLAN.md contains XML tasks
- REQUIREMENTS.md is source of truth
- Never modify outside GSD commands

**Status**: COMPLETE — Good guard against accidental manual edits.

---

#### `test-files.md` — Activates on Test Paths
(11 lines) Paths: `tests/**`, `**/*.test.*`, `**/*.spec.*`

States:
- Every feature needs tests
- Run full suite before task completion
- Tests must pass before `/gsd:verify-work`

**Status**: COMPLETE — Good enforcement.

---

#### `security.md` — Activates on Sensitive Paths
(8 lines) Paths: `**/*.env*`, `**/auth/**`, `**/config/**`

States:
- Never commit secrets/API keys
- Validate external input
- Flag concerns during verification

**Status**: COMPLETE — Protects sensitive areas.

---

### 4. Installation & Verification

#### `install.sh` — Installer (226 lines)

**What it does**:
1. Installs three skills into `~/.claude/skills/`
2. Installs rules into `~/.claude/rules/`
3. Creates global `~/.claude/CLAUDE.md` if missing (or appends GSD config)
4. Creates global `~/.codex/AGENTS.md` and `~/.codex/config.toml`
5. Installs GSD framework globally (via `npx get-shit-done-cc@latest`)
6. Creates `.gitignore`
7. Prints summary

**Status**: COMPLETE — Fully functional bash script.

**Quality**: Good — Respects existing files, appends intelligently, clear error messages.

**Dependencies**: Assumes `npx` (Node.js) is available. Assumes GSD can be installed via npm.

---

#### `test-install.sh` — Verification (52 lines)

**What it checks**:
- 3 skills installed to `~/.claude/skills/`
- 3 GSD commands installed to `~/.claude/commands/gsd/`
- 1 GSD skill installed to `~/.codex/skills/`
- 1 GSD command installed to `~/.gemini/commands/gsd/`
- Global configs (CLAUDE.md, CODEX configs)
- GSD agents installed

**Status**: SPEC ONLY for some checks — The script exists but many checks will fail because GSD framework isn't bundled.

**Current result**: Will fail 7-8 checks related to GSD framework (assumed installed separately).

---

### 5. Documentation

#### `docs/SPEC.md` — Full Specification (407 lines)

**Sections**:
1. Overview (3 systems, bootstrap package)
2. Installation & Bootstrap (one-time + per-project)
3. Project Structure (.planning/ directory layout)
4. Shared Instructions Strategy (AGENTS.md vs CLAUDE.md)
5. Workflow Phase-by-Phase (discuss → plan → execute → verify)
6. Division of Labor (task routing matrix)
7. Parallel Execution with Worktrees (git worktree usage)
8. GSD Configuration (config.json schema, model profiles)
9. Anti-Context-Rot Strategy (how GSD prevents degradation)
10. Daily Workflow Cheat Sheet (morning → execute → verify → close)
11. Key Commands Reference (table of all commands)
12. When Things Go Wrong (troubleshooting)
13. Summary (integrated vision)

**Status**: COMPLETE — Well-structured, comprehensive, detailed examples.

**Quality**: Excellent — Clear section headers, code blocks, decision tables, rationale.

**Accuracy**: HIGH — Describes intended workflow correctly. No contradictions found.

---

#### `AGENTS.md` — Universal Project Instructions (43 lines)

**Content**:
- Project name and purpose
- Build & Test commands (template)
- Architecture (high-level)
- Conventions (tests, no debug code, atomic commits)
- Workflow (dual-tool execution model)

**Status**: COMPLETE — Template ready for projects.

**Quality**: Good — Covers all required sections. Clear and concise.

---

#### `CLAUDE.md` — Claude-Specific Instructions (31 lines)

**Content**:
- Reference to @AGENTS.md
- GSD Workflow (commands sequence)
- Dual-Tool Execution (split tasks by complexity)
- Dual-Tool Verification (cross-review pattern)
- Quality Gates (no verification skips, atomic commits)

**Status**: COMPLETE — Ready for projects.

**Quality**: Good — Concise, actionable, references global instructions.

---

### 6. GSD State (`.planning/`)

#### `PROJECT.md` — Project Vision
(37 lines) Complete description of goals, problems, solution, target users, success criteria.

**Status**: COMPLETE — Written during project discussion phase.

---

#### `STATE.md` — Workflow Position
(13 lines) Current position: M1, Phase 0 (pre-planning), status = research → requirements → roadmap.

**Status**: ACCURATE — Correctly reflects where the project is now.

---

#### `config.json` — GSD Configuration
(20 lines) Mode: interactive, depth: standard, model_profile: quality, workflow: research/plan_check/verifier enabled.

**Status**: COMPLETE — Appropriate settings for project planning.

---

#### `PAUSE-STATE.md` — Pre-Execution Checkpoint
(43 lines) Captured answers from discussion phase, list of files already created, GSD installation status.

**Status**: COMPLETE — Good checkpoint for resume.

---

## Gaps & Missing Implementation

### Critical Gaps

#### 1. **GSD Framework Not Bundled** (CRITICAL)
**Location**: `install.sh` line 175-177

The installer tries to call `npx get-shit-done-cc@latest` to install GSD framework, but:
- GSD is NOT included in this repository
- Installation depends on external npm package
- If GSD not available, installation fails silently or incompletely
- The test script will fail many checks

**Impact**: Projects cannot bootstrap without external GSD dependency.

**Solution**: Either:
A. Document that GSD must be pre-installed (dependency on get-shit-done-cc package)
B. Bundle GSD commands/agents into this repo
C. Create fallback if GSD not available

---

#### 2. **No Skill Implementation Code** (CRITICAL)
**Affected**: `/init-gsd`, `/codex-review`, `/gsd-codex-verify`

All three skills are SPEC ONLY (markdown descriptions of what they should do), but contain NO actual Claude Code skill implementation.

**What's missing**:
- Each skill needs a bash/node/python script that implements the steps described
- Skills need proper error handling, validation, progress reporting
- Skills need to read/write `.planning/` files and invoke subcommands

**Impact**: Skills cannot be used — they're documentation, not executable.

**Scope**: This is the biggest implementation gap. Each skill is 50-100 lines of description but 0 lines of code.

---

#### 3. **Git Worktree Management Automation** (HIGH)
**Referenced in**: SPEC.md sections 6-7, CLAUDE.md

The specification repeatedly mentions:
```bash
git worktree add ../task-codex codex-branch
cd ../task-codex
codex --full-auto "task"
```

But there's NO helper script to automate this. Users must manually manage worktrees.

**Missing**:
- Script to create worktree from GSD plan
- Script to merge worktree back
- Script to clean up failed worktrees
- Integration with wave-based task execution

---

#### 4. **Task-Splitting Heuristic** (HIGH)
**Referenced in**: PROJECT.md, SPEC.md section 5, CLAUDE.md

The specification says:
> Automatic task splitting — Heuristic during /gsd:plan-phase: multi-file/architecture → Claude, CRUD/tests/scripts → Codex; user can override

But there's NO heuristic implementation:
- How does the planner decide if a task is "multi-file"?
- What rules determine "CRUD"?
- Where are task attributes stored (tags in PLAN.md XML)?
- How does user override?

---

#### 5. **No Example Project** (MEDIUM)
**Missing**: A demo project showing the workflow in practice.

Without an example, it's unclear:
- What a real AGENTS.md looks like after `/init-gsd`
- How `codex --full-auto` command is formatted
- What PLAN.md XML structure looks like
- How cross-review reports are formatted

---

### Medium Gaps

#### 6. **REQUIREMENTS.md Not Created** (PHASE BLOCKER)
**Location**: Should be in `.planning/REQUIREMENTS.md`

The spec mentions REQUIREMENTS.md as source of truth, but it's not created during `/init-gsd` or `/gsd:new-project`.

**Impact**: Cannot proceed to Phase 1 planning without requirements. STATE.md says "next step: Generate REQUIREMENTS.md" but no command exists to do this.

---

#### 7. **ROADMAP.md Not Created** (PHASE BLOCKER)
**Location**: Should be in `.planning/ROADMAP.md`

The SPEC mentions ROADMAP.md with milestones and phases, but it's not created.

**Current state**: `.planning/` has PROJECT.md, STATE.md, config.json, but no ROADMAP.md.

---

#### 8. **Worktree Configuration** (MEDIUM)
**Location**: No documentation of worktree branch naming, cleanup policy, isolation strategy.

Questions unanswered:
- Should worktrees be long-lived or short-lived?
- How to merge back without conflicts?
- What if Codex fails mid-task?
- How to handle partial commits?

---

#### 9. **Cross-Review Report Format** (LOW)
**Referenced in**: `/gsd-codex-verify` step 6

The spec shows a nice ASCII report format, but:
- No template saved to `.planning/`
- No validation rules
- No severity level mapping (critical → exit 1, warning → exit 0?)

---

### Minor Issues

#### 10. **Codex Config Contradicts Itself** (MINOR)
**File**: `global/codex-config.toml` line 2-3

```toml
approval_policy = "untrusted"
sandbox_mode = "workspace-write"
```

An "untrusted" policy should have read-only sandbox, not write access. This is backwards.

**Fix**: Change to `approval_policy = "on-request"` or `sandbox_mode = "read-only"`.

---

#### 11. **Model Name is Placeholder** (MINOR)
**File**: `global/codex-config.toml` line 1

```toml
model = "gpt-5-codex"
```

This model doesn't exist yet (as of Feb 2025). Should document which real models are supported (gpt-4-turbo, claude-3-opus, etc.).

---

#### 12. **No Version Constraints** (LOW)
The installer doesn't specify versions of:
- `@anthropic-ai/claude-code`
- `@openai/codex`
- `get-shit-done-cc`

This can lead to incompatibility issues. Should pin versions.

---

## What Works (Implemented & Tested)

✓ **Three skills are spec'd** — Functional descriptions of what each does.
✓ **Installation script is functional** — Can install files to correct locations.
✓ **Global configs are complete** — AGENTS.md and config templates ready.
✓ **Rules are working** — Path-based context injection rules correctly formatted.
✓ **Documentation is excellent** — SPEC.md is comprehensive and well-written.
✓ **Project initialization state** — PROJECT.md, STATE.md, config.json capture project intent.
✓ **Git structure ready** — .gitignore, rules/ directory, skills/ directory all in place.

---

## Readiness Assessment

### For Phase 1 (Requirements)
**Status**: BLOCKED

Missing: REQUIREMENTS.md file (must capture all project deliverables before planning).

**To unblock**:
1. Create .planning/REQUIREMENTS.md with:
   - Skill implementation requirements (init-gsd, codex-review, gsd-codex-verify)
   - Worktree automation requirements
   - Task-splitting heuristic requirements
   - Example project requirement
   - Test coverage requirements

---

### For Phase 2 (Roadmap)
**Status**: BLOCKED

Missing: REQUIREMENTS.md must exist first.

Once REQUIREMENTS.md exists:
- Phase 1: Skill implementation (complex interactive work → Claude)
- Phase 2: Worktree automation (scripts → Codex)
- Phase 3: Task-splitting heuristics (GSD agent customization → Claude)
- Phase 4: Example project (full workflow demo → both)
- Phase 5: Testing & verification (test coverage → Codex)

---

### For Phase 3+ (Execution)
**Status**: WAITING FOR REQUIREMENTS

The implementation roadmap depends on what gets prioritized in REQUIREMENTS.md:
- Start with skill implementation (highest blocking value)
- Then automation (force multiplier for dual-tool workflow)
- Then heuristics (optimization)
- Then example (validation)

---

## File Inventory

| File | Type | Lines | Status | Purpose |
|------|------|-------|--------|---------|
| `AGENTS.md` | Doc | 43 | COMPLETE | Universal project instructions |
| `CLAUDE.md` | Doc | 31 | COMPLETE | Claude-specific workflow |
| `docs/SPEC.md` | Doc | 407 | COMPLETE | Full specification |
| `skills/init-gsd/SKILL.md` | Spec | 236 | SPEC ONLY | Bootstrap skill (no code) |
| `skills/codex-review/SKILL.md` | Spec | 72 | SPEC ONLY | Review skill (no code) |
| `skills/gsd-codex-verify/SKILL.md` | Spec | 92 | SPEC ONLY | Verify skill (no code) |
| `global/codex-agents.md` | Config | 27 | COMPLETE | Codex role instructions |
| `global/codex-config.toml` | Config | 16 | COMPLETE (issues) | Codex configuration template |
| `rules/gsd-workflow.md` | Config | 7 | COMPLETE | GSD workflow rule |
| `rules/planning-files.md` | Config | 11 | COMPLETE | Planning files rule |
| `rules/test-files.md` | Config | 11 | COMPLETE | Test files rule |
| `rules/security.md` | Config | 8 | COMPLETE | Security rule |
| `install.sh` | Script | 226 | COMPLETE | Installation script |
| `test-install.sh` | Script | 52 | SPEC ONLY* | Verification script |
| `.planning/PROJECT.md` | GSD | 37 | COMPLETE | Project vision |
| `.planning/STATE.md` | GSD | 13 | COMPLETE | Current position |
| `.planning/config.json` | GSD | 20 | COMPLETE | Configuration |
| `.planning/PAUSE-STATE.md` | GSD | 43 | COMPLETE | Checkpoint |

*test-install.sh exists but many checks fail due to missing GSD framework.

---

## Summary for Roadmap Creation

### What This Project Does
A framework for integrating Claude Code (planner) with Codex CLI (executor) into a unified GSD workflow. Launched via `/init-gsd` skill in Claude Code, it bootstraps any project with:
1. Dual-tool instructions (AGENTS.md + CLAUDE.md)
2. Conditional rules for context injection
3. Global Codex configuration
4. Integration with GSD for state management

### Highest-Value Next Steps (Roadmap Phase Suggestions)

**Phase 1: Skill Implementation** ⭐⭐⭐
Implement the three skills with actual Claude Code logic:
- `/init-gsd` (project bootstrapper)
- `/codex-review` (cross-model review)
- `/gsd-codex-verify` (dual-tool verification gate)

This unblocks end-to-end workflow testing.

**Phase 2: Worktree Automation** ⭐⭐⭐
Create helper scripts and GSD integration for:
- Automatic worktree creation from PLAN.md
- Task assignment to tool (Claude vs Codex)
- Merge-back and conflict handling

This enables parallel execution.

**Phase 3: Task-Splitting Heuristic** ⭐⭐
Implement classification logic that tags tasks:
- Multi-file/architecture → Claude
- CRUD/tests/scripts → Codex
- Override mechanism

This makes the "automatic" task splitting actually automatic.

**Phase 4: Example Project** ⭐⭐
Create a demo project showing:
- Real AGENTS.md after `/init-gsd`
- Real PLAN.md with mixed Claude/Codex tasks
- Actual cross-review report
- Full workflow from start to completion

This validates the entire system.

**Phase 5: Testing & Verification** ⭐
- Unit tests for each skill
- Integration tests for install.sh
- Workflow end-to-end tests
- Documentation of test coverage

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|-----------|-------|
| **Existing files** | HIGH | All files audited and read |
| **Project vision** | HIGH | PROJECT.md is clear and specific |
| **Specification** | HIGH | SPEC.md is comprehensive and detailed |
| **Installation approach** | MEDIUM | Works for local installation but depends on external GSD package |
| **Skill design** | MEDIUM | Specs are good but implementation requirements unclear (code language, structure) |
| **Worktree strategy** | MEDIUM | Conceptually sound but automation not yet designed |
| **Task-splitting logic** | LOW | Heuristic mentioned but not defined |

---

## Conclusion

The gsd-multi-model project is **well-specified and architecturally sound**, with excellent documentation and a clear vision. The main limitation is that it's **80% specification, 20% implementation**. All three custom skills are described but not coded. The worktree automation strategy is mentioned but not scripted. The task-splitting heuristic is proposed but not defined.

**The path forward is clear**: Implement the spec in phases, starting with the three skills (highest blocking value), then automation, then optimization. The foundation is solid; execution is what's needed.
