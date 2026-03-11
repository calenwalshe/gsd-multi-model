# Phase 02: Deterministic Gates - Research

**Researched:** 2026-03-11
**Domain:** Pre-commit quality gates for AI-driven workflow (shell scripts + Node.js CLI + Markdown skill instructions)
**Confidence:** HIGH

## Summary

Phase 02 adds deterministic quality gates to the GSD execute phase. Currently, task commits happen via direct `git add`/`git commit` in the execute-plan workflow with no automated checks. The gates must intercept the commit flow to run linters, validate architecture constraints, and execute structural tests -- blocking the commit if any check fails.

The system is a **skill framework** (Markdown instructions + `gsd-tools.cjs` CLI). Gates are not traditional git pre-commit hooks -- they are procedural checks encoded in the workflow instructions that executor agents follow, backed by a validation script that `gsd-tools.cjs` invokes. This approach is more reliable than git hooks in the Claude Code agent context because agents control the commit flow directly.

**Primary recommendation:** Add a `gate` command to `gsd-tools.cjs` that runs all configured checks, returning a structured pass/fail JSON result. Modify the execute-plan workflow's `<task_commit>` section to call this gate before every `git commit`. Define `.architecture.json` as a simple module-boundary + dependency-direction schema validated by a purpose-built script.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None -- all decisions are Claude's Discretion.

### Claude's Discretion
All implementation decisions deferred to Claude's judgment.
/gsd:drive auto-generated this context -- no user discussion occurred.
Research and planning agents should make reasonable default choices.

### Deferred Ideas (OUT OF SCOPE)
None -- auto-generated context
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GATE-01 | Execute phase runs project linters before allowing task commit (fail = task blocked) | Gate runner in gsd-tools.cjs + modified task_commit protocol in execute-plan.md |
| GATE-02 | `.architecture.json` format defines allowed dependency directions between modules | Architecture schema design + import validator script |
| GATE-03 | Structural test scaffolding that agents run against their own output before commit | Structural test runner that checks file existence, export shapes, naming conventions |
| GATE-04 | Gate failures produce actionable error messages (what failed, what to fix) | Structured JSON error format from gate runner with human-readable formatting |
</phase_requirements>

## Standard Stack

### Core
| Component | Type | Purpose | Why Standard |
|-----------|------|---------|--------------|
| `gsd-tools.cjs` | Node.js CLI (existing) | Gate runner command (`gate run`) | Already the central CLI tool; avoids new dependencies |
| `bin/gate-check.sh` | Shell script (new) | Lightweight gate orchestrator callable from workflow | Shell is the execution environment for all GSD workflow steps |
| `.architecture.json` | JSON config (new) | Module boundary + dependency direction rules | Simple, parseable, no tooling dependencies |
| `.planning/config.json` | JSON config (existing) | Gate configuration (which checks enabled, lint commands) | Already used for all GSD config |

### Supporting
| Component | Type | Purpose | When to Use |
|-----------|------|---------|-------------|
| Project linters (eslint, ruff, etc.) | External tools | The actual lint checks | When project has linters configured |
| `node --check` / `bash -n` | Built-in | Syntax validation fallback | When no project linter exists |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom gate in gsd-tools.cjs | Git pre-commit hooks (husky/lefthook) | Hooks bypass-able with --no-verify; agents don't always use git CLI directly; hooks don't produce structured output |
| Shell-based gate script | Python/Node standalone tool | Extra dependency; shell matches existing GSD execution model |
| `.architecture.json` custom format | depcheck / madge / eslint-plugin-import | Too heavy; require project-specific install; we need cross-language boundary checks, not just JS imports |

## Architecture Patterns

### Recommended Project Structure (new files)
```
bin/
  gate-check.sh           # Gate orchestrator (runs all enabled checks)
  validate-architecture.sh # .architecture.json import validator
skills/
  gsd-drive/              # (existing, unchanged)
.architecture.json        # Module boundary rules (per-project, user-created)
```

### Changes to Existing Files
```
.planning/config.json          # Add gates.* config section
gsd-tools.cjs                  # Add 'gate' command
execute-plan.md (in GSD base)  # Modify <task_commit> to call gate before commit
```

### Pattern 1: Gate Runner Architecture

**What:** A single entry point (`bin/gate-check.sh` or `gsd-tools.cjs gate run`) that orchestrates all enabled checks and returns structured results.

**When to use:** Before every task commit during execute phase.

**Design:**

```bash
# bin/gate-check.sh
# Input: list of staged files (from git diff --cached --name-only)
# Output: JSON to stdout with pass/fail + details
# Exit code: 0 = all gates pass, 1 = gate failure

STAGED_FILES=$(git diff --cached --name-only)

RESULTS=()

# 1. Lint gate (if configured)
if [ -n "$LINT_COMMAND" ]; then
  LINT_OUTPUT=$(eval "$LINT_COMMAND" 2>&1)
  LINT_EXIT=$?
  # ... collect result
fi

# 2. Architecture gate (if .architecture.json exists)
if [ -f ".architecture.json" ]; then
  ARCH_OUTPUT=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" gate check-architecture --files $STAGED_FILES 2>&1)
  ARCH_EXIT=$?
  # ... collect result
fi

# 3. Structural tests (if defined in plan)
if [ -n "$STRUCTURAL_TESTS" ]; then
  # ... run structural checks
fi

# Output structured result
echo '{"passed": true/false, "gates": [...]}'
```

### Pattern 2: Task Commit with Gate Check

**What:** Modified commit protocol that runs gates before allowing commit.

**Current flow (execute-plan.md `<task_commit>`):**
```
1. git status --short
2. git add <files>
3. git commit -m "..."
4. Record hash
```

**New flow:**
```
1. git status --short
2. git add <files>
3. RUN GATE CHECK on staged files
4. If gate fails: print actionable error, UNSTAGE, STOP (do not commit)
5. If gate passes: git commit -m "..."
6. Record hash
```

### Pattern 3: Architecture Constraint Schema

**What:** `.architecture.json` defines module boundaries and allowed dependency directions.

**Schema design:**
```json
{
  "version": "1.0",
  "modules": {
    "skills/*": {
      "description": "Claude Code skills",
      "can_import": ["bin/*"],
      "cannot_import": ["global/*", ".planning/*"]
    },
    "bin/*": {
      "description": "CLI scripts and tools",
      "can_import": [],
      "cannot_import": ["skills/*"]
    },
    "global/*": {
      "description": "Global config templates",
      "can_import": [],
      "cannot_import": ["skills/*", "bin/*"]
    }
  },
  "rules": [
    {
      "name": "no-circular-skill-deps",
      "description": "Skills must not import from other skills",
      "from": "skills/*/",
      "cannot_reach": "skills/*/"
    }
  ]
}
```

**Validation approach:** For each staged file, determine which module it belongs to. Scan for import/require/source statements. Check if any imports violate the `cannot_import` rules. For Markdown files (skills), check `@` references. For shell scripts, check `source` statements. For JS/TS, check `require`/`import`.

### Pattern 4: Structural Test Scaffolding

**What:** Agents define structural assertions in the plan that are checked before commit.

**Plan-level structural tests (in PLAN.md):**
```xml
<structural_tests>
  <test name="exports-exist">
    <description>New module exports required functions</description>
    <check type="file-exists" path="bin/gate-check.sh" />
    <check type="file-contains" path="bin/gate-check.sh" pattern="gate_run" />
    <check type="executable" path="bin/gate-check.sh" />
  </test>
  <test name="no-hardcoded-paths">
    <description>Scripts use $HOME not hardcoded paths</description>
    <check type="file-not-contains" path="bin/gate-check.sh" pattern="/home/[a-z]+/" />
  </test>
</structural_tests>
```

**Runtime check types:**
- `file-exists`: File exists at path
- `file-contains`: File contains regex pattern
- `file-not-contains`: File does NOT contain regex pattern
- `executable`: File has execute permission
- `exports-function`: JS/TS module exports named function
- `json-valid`: File is valid JSON
- `json-has-key`: JSON file contains key at path

### Anti-Patterns to Avoid
- **Git hooks for agent gating:** Agents can bypass hooks, hooks don't produce structured output, hooks assume interactive terminal
- **All-or-nothing gates:** Always allow `--skip-gates` escape hatch for emergencies (logged in SUMMARY.md)
- **Lint the entire project on every commit:** Only lint staged/changed files for speed
- **Architecture validation on planning files:** Only validate source files, not `.planning/` artifacts

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Linting | Custom lint rules | Project's existing linter (eslint, ruff, etc.) | Linters are mature; just invoke them |
| JSON schema validation | Custom JSON parser | `node -e "JSON.parse(...)"` or `jq` | Standard tools handle edge cases |
| File glob matching | Custom glob implementation | Node.js `minimatch` (already available) or shell `find` | Glob matching has many edge cases |
| Import parsing | Full AST parser | Regex-based pattern matching | For boundary checks, regex is sufficient; full AST is overkill |

**Key insight:** The gate system is an orchestrator, not a checker. It calls existing tools (linters, validators) and formats their output. Keep the gate runner thin.

## Common Pitfalls

### Pitfall 1: Gate Runs on Wrong Files
**What goes wrong:** Gate checks files that aren't staged, or misses staged files
**Why it happens:** Using `git status` instead of `git diff --cached --name-only`
**How to avoid:** Always use `git diff --cached --name-only` to get the exact staged file list
**Warning signs:** Gates pass but committed code has violations

### Pitfall 2: Lint Command Not Configured
**What goes wrong:** Gate tries to run linter but project has no linter, causing spurious failures
**Why it happens:** Assuming every project has eslint/ruff
**How to avoid:** Make lint gate opt-in via `config.json`. If `gates.lint_command` is empty, skip lint gate. Auto-detect common linter configs (.eslintrc, pyproject.toml, etc.) as hint but don't assume.
**Warning signs:** "command not found" errors from gate runner

### Pitfall 3: Architecture Validation Too Strict for Markdown Skills
**What goes wrong:** Architecture validator flags `@` references in skill Markdown as import violations
**Why it happens:** Treating Markdown `@path/to/file` as a real import
**How to avoid:** Architecture validation should focus on executable files (`.sh`, `.js`, `.ts`, `.py`). Markdown references are documentation, not runtime dependencies.
**Warning signs:** False positives on every skill file edit

### Pitfall 4: Gate Blocks Planning Doc Commits
**What goes wrong:** Gates run on `.planning/` file commits and fail (no linter for Markdown planning docs)
**Why it happens:** Not distinguishing code commits from planning metadata commits
**How to avoid:** Gates only run on task commits (the `<task_commit>` flow), not on `gsd-tools.cjs commit` (planning docs). The two commit paths are already separate.
**Warning signs:** Planning doc commits blocked by linter errors

### Pitfall 5: Slow Gates Break Flow
**What goes wrong:** Gates take 30+ seconds, making the execute phase painfully slow
**Why it happens:** Running full project lint instead of staged-file-only lint
**How to avoid:** Always pass specific file list to linter. Set a timeout (10s default). If timeout, warn but don't block.
**Warning signs:** Execute phase taking 3x longer than before

## Code Examples

### Gate Configuration in config.json

```json
{
  "gates": {
    "enabled": true,
    "lint": {
      "enabled": true,
      "command": "npx eslint --no-warn-ignored {files}",
      "auto_detect": true
    },
    "architecture": {
      "enabled": true,
      "config_path": ".architecture.json"
    },
    "structural": {
      "enabled": true
    },
    "timeout_seconds": 10,
    "on_timeout": "warn"
  }
}
```

### Gate Result JSON Format

```json
{
  "passed": false,
  "duration_ms": 342,
  "gates": [
    {
      "name": "lint",
      "passed": true,
      "files_checked": 3,
      "message": "All files pass lint"
    },
    {
      "name": "architecture",
      "passed": false,
      "violations": [
        {
          "file": "skills/init-gsd/SKILL.md",
          "rule": "no-circular-skill-deps",
          "message": "skills/init-gsd/ imports from skills/codex-review/ — skills must not import other skills",
          "fix": "Move shared logic to bin/ or a shared utility"
        }
      ]
    }
  ]
}
```

### Actionable Error Message Format (GATE-04)

```
=== GATE FAILED ===

Lint: PASS (3 files)
Architecture: FAIL

  VIOLATION: skills/init-gsd/SKILL.md
  Rule: no-circular-skill-deps
  Issue: skills/init-gsd/ references skills/codex-review/
  Fix: Move shared logic to bin/ or a shared utility

Structural: SKIPPED (no tests defined)

Task commit blocked. Fix violations and retry.
```

### Modified task_commit Protocol (for execute-plan.md)

```markdown
<task_commit>
## Task Commit Protocol

After each task (verification passed, done criteria met), commit immediately.

**1. Check:** `git status --short`

**2. Stage individually** (NEVER `git add .` or `git add -A`):
```bash
git add src/api/auth.ts
git add src/types/user.ts
```

**3. Run gates** (if enabled in config):
```bash
GATE_RESULT=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" gate run --raw 2>/dev/null)
GATE_PASSED=$(echo "$GATE_RESULT" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).passed))")
```

If `GATE_PASSED` is `false`:
- Print the gate failure message (from GATE_RESULT)
- **Fix the violations** (lint errors, architecture issues)
- Re-stage fixed files
- Re-run gates
- Only proceed when gates pass

**4. Commit:**
```bash
git commit -m "{type}({phase}-{plan}): {description}"
```

**5. Record hash:**
```bash
TASK_COMMIT=$(git rev-parse --short HEAD)
```
</task_commit>
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No pre-commit checks | Advisory verification only (verify-work) | v1.0 | Bad code caught late, after full phase execution |
| Git pre-commit hooks | Workflow-integrated gates | Phase 02 (this phase) | Agents can't bypass; structured output; works in non-interactive context |

## Integration Points

### Where Gates Hook Into Existing System

1. **`execute-plan.md` `<task_commit>` section** -- Add gate check step between staging and committing
2. **`gsd-tools.cjs`** -- Add `gate` command (run, check-architecture, check-structural)
3. **`.planning/config.json`** -- Add `gates` configuration section
4. **`execute-phase.md`** -- No changes needed (delegates to execute-plan)
5. **`gsd-drive` skill** -- No changes needed (calls execute-phase which calls execute-plan)

### What Does NOT Change
- Planning doc commits (`gsd-tools.cjs commit`) -- no gates on docs
- The drive workflow state machine
- Checkpoint handling
- SUMMARY.md creation
- Phase verification (`verify-work`)

## Open Questions

1. **Where does the modified execute-plan.md live?**
   - Currently: `/home/agent/.claude/get-shit-done/workflows/execute-plan.md` (GSD base)
   - Option A: Modify GSD base file directly (fragile -- base updates would overwrite)
   - Option B: Override via gsd-multi-model skill that wraps execute-plan
   - Option C: Gate logic in gsd-tools.cjs CLI, only add one line to execute-plan referencing it
   - **Recommendation:** Option C. The gate check is a single CLI call. Add it to the `<task_commit>` section of execute-plan.md. The `gsd-tools.cjs gate run` command is a no-op if gates are not configured, so it's safe to add to the base workflow.

2. **How does the agent know what structural tests to run?**
   - Structural tests are defined per-plan in `<structural_tests>` XML blocks
   - The gate runner reads the current plan file to find these blocks
   - If no structural tests are defined, the structural gate is skipped
   - **Recommendation:** Pass plan path to gate runner: `gsd-tools.cjs gate run --plan-path <path>`

3. **Should gates run on Codex autonomous tasks too?**
   - Codex tasks run in separate worktrees via `codex-task.sh`
   - Codex commits independently
   - **Recommendation:** Yes, but via a separate mechanism. Add gate-check to `codex-task.sh` post-execution verification. This is a nice-to-have; core requirement is Claude Code executor agents.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash + node assertions (no external test framework) |
| Config file | none -- tests are shell scripts in `bin/test-*.sh` |
| Quick run command | `bash bin/test-gate-check.sh` |
| Full suite command | `for f in bin/test-*.sh; do bash "$f"; done` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GATE-01 | Lint gate blocks commit on failure | integration | `bash bin/test-gate-check.sh` | No -- Wave 0 |
| GATE-02 | Architecture validator checks imports | unit | `bash bin/test-validate-architecture.sh` | No -- Wave 0 |
| GATE-03 | Structural tests run against output | unit | `bash bin/test-gate-check.sh` (structural section) | No -- Wave 0 |
| GATE-04 | Actionable error messages on failure | unit | `bash bin/test-gate-check.sh` (output format) | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `bash bin/test-gate-check.sh`
- **Per wave merge:** `for f in bin/test-*.sh; do bash "$f"; done`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `bin/test-gate-check.sh` -- covers GATE-01, GATE-03, GATE-04
- [ ] `bin/test-validate-architecture.sh` -- covers GATE-02
- [ ] Sample `.architecture.json` for testing

## Sources

### Primary (HIGH confidence)
- Existing codebase analysis: `gsd-tools.cjs` commit flow (commands.cjs L216-262)
- Existing codebase analysis: `execute-plan.md` task_commit protocol
- Existing codebase analysis: `execute-phase.md` orchestration flow
- Existing codebase analysis: `.planning/config.json` configuration schema
- Existing codebase analysis: `git-integration.md` commit conventions

### Secondary (MEDIUM confidence)
- GSD workflow patterns observed across v1.0-v2.0 milestones

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - based on direct codebase analysis, extending existing patterns
- Architecture: HIGH - straightforward extension of existing CLI tool and workflow
- Pitfalls: HIGH - derived from understanding actual execution flow
- Integration points: HIGH - traced exact code paths where changes are needed

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable domain, internal tooling)
