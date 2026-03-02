# Codex CLI Integration: Capabilities & Patterns for gsd-multi-model

**Research Date:** 2026-03-02
**Domain:** Codex CLI as autonomous coder in dual-tool workflow
**Overall Confidence:** HIGH (official OpenAI docs + real-world integration patterns)

---

## Executive Summary

Codex CLI is production-ready for fire-and-forget autonomous execution within gsd-multi-model. The system provides:

1. **Robust command syntax** with flags for approval control, sandbox isolation, and model selection
2. **Project context auto-discovery** via AGENTS.md (with fallback filenames like CLAUDE.md)
3. **Two execution models**: interactive terminal UI or non-interactive `codex exec` for scripts/CI
4. **Git worktree compatible** — multiple Codex agents run in parallel without conflicts
5. **Structured output capture** via JSON, schemas, and transcripts for result verification

**Integration strategy:** Use `codex exec --full-auto` in git worktrees for autonomous tasks, with Codex reading the project's AGENTS.md/CLAUDE.md for shared context. Results captured as JSON/JSONL for validation before code review.

**Known limitations:** Connection stability (v0.87.0), rate limiting on large repos, context degradation in long conversations, MCP/tool integration complexity.

---

## 1. Codex CLI Command Syntax & Flags

### Core Commands

| Command | Mode | Use Case |
|---------|------|----------|
| `codex "prompt"` | Interactive TUI | Real-time coding with approval gates |
| `codex exec "prompt"` | Non-interactive | Scripted/CI execution, returns output to stdout |
| `codex app` | Desktop | macOS only, graphical interface |
| `codex resume` | Session recovery | Continue previous work from transcripts |
| `codex login` | Auth | Authenticate with OpenAI/ChatGPT credentials |
| `codex cloud` | Cloud tasks | Submit jobs to Codex cloud infrastructure |

### Global Flags (High-Impact for gsd-multi-model)

| Flag | Values | Purpose | For Fire-and-Forget |
|------|--------|---------|-------------------|
| `--full-auto` | boolean | Shortcut: sets `--ask-for-approval never` + `--sandbox workspace-write` | **YES** — enables fully autonomous execution |
| `--ask-for-approval, -a` | untrusted, on-request, never | Control when Codex asks for approval before executing | `never` for fire-and-forget |
| `--sandbox, -s` | read-only, workspace-write, danger-full-access | Restrict what filesystem/network ops are allowed | `workspace-write` is safe default |
| `--model, -m` | gpt-5.3-codex, gpt-5.3-codex-spark | Codex model to use | `gpt-5.3-codex` recommended for most tasks |
| `--cd, -C` | path | Working directory for the task | Use when running from worktree |
| `--profile, -p` | string | Load config profile from ~/.codex/config.toml | For task-specific settings |
| `--config, -c` | key=value | Override config inline | Useful in CI/scripts |
| `--search` | boolean | Enable live web search during execution | Disable for isolated/offline tasks |
| `--output-schema` | path | JSON Schema file for structured final output | For programmatic result parsing |
| `--json` | boolean | Stream JSONL events to stdout instead of TUI | For scripting/result capture |
| `--ephemeral` | boolean | Don't persist session files (important for CI/automation) | Use in CI to avoid clutter |
| `--add-dir` | path | Grant additional directories write access | For multi-workspace tasks |
| `--image, -i` | path[,path...] | Attach image files to the prompt | For visual debugging/documentation |
| `--dangerously-bypass-approvals-and-sandbox, --yolo` | boolean | Skip ALL safety checks | **DANGEROUS** — only for trusted scripts |

### Recommended Flags for gsd-multi-model

```bash
# Standard fire-and-forget (safest, recommended)
codex exec --full-auto --ephemeral "Implement tasks per .planning/PLAN.md"

# With output capture for verification
codex exec --full-auto --json --ephemeral "..." > /tmp/codex-result.jsonl

# With structured output schema
codex exec --full-auto --output-schema schema.json -o result.json "..."

# Non-interactive in CI/automation
CODEX_API_KEY="$KEY" codex exec --full-auto --ephemeral "..."

# From specific worktree directory
codex exec --cd /path/to/worktree --full-auto "..."
```

**Confidence:** HIGH — official OpenAI documentation with real usage patterns.

---

## 2. Codex Sandbox Modes & Security Model

### Sandbox Architecture

Codex uses a **two-layer security model**: sandboxing controls *what operations are technically possible*, while approval policies control *when user confirmation is required*.

**OS-Specific Implementations:**
- **macOS:** Seatbelt policies via `sandbox-exec` with profiles mapped to sandbox mode
- **Linux:** Landlock + seccomp by default; optional bwrap with proxy-only network bridge
- **Windows:** WSL when available (inherits Linux semantics), or native Windows sandbox (unelevated/elevated)

### Sandbox Modes

| Mode | File Access | Shell Commands | Network | Use Case |
|------|------------|-----------------|---------|----------|
| **read-only** | Read only, no edits | Cannot execute | Disabled | Safe code review, analysis tasks |
| **workspace-write** | Read + edit in workspace | Execute with restrictions | Disabled by default | **Recommended for fire-and-forget tasks** |
| **danger-full-access** | Unrestricted | Unrestricted | Enabled | **Avoid — use only if absolutely necessary** |

### Protected Paths (Even in Writable Modes)

These directories remain read-only regardless of sandbox mode:
- `.git/` — version control metadata
- `.agents/` — Codex automation files
- `.codex/` — Codex configuration
- `.planning/` — GSD state files (important for gsd-multi-model!)

**This is critical:** GSD planning files are automatically protected from accidental Codex modification, preventing state corruption.

### Approval Policies

Combined with sandbox, approval policies control *when* user interaction is required:

| Policy | Behavior |
|--------|----------|
| **suggest** (default) | Ask for approval before every action |
| **auto-edit** | Auto-apply file changes, ask for shell commands |
| **on-request** | Paired with --full-auto for low-friction local work |
| **untrusted** | Ask before running state-mutating commands |
| **never** | Fully automatic (use only with `--full-auto` + trusted tasks) |

### Recommended Security Configuration for gsd-multi-model

```bash
# In CI/scripts: fully autonomous with protection
codex exec \
  --full-auto \                        # approval=never, sandbox=workspace-write
  --ephemeral \                        # Don't persist session files
  --ask-for-approval never \           # Explicit confirmation
  "Implement tasks per .planning/PLAN.md"

# Locally during development: interactive approval for safety
codex exec \
  --sandbox workspace-write \
  --ask-for-approval on-request \
  "Implement tasks"

# For read-only analysis/review tasks
codex exec \
  --sandbox read-only \
  "Review the repository for security issues"
```

**Confidence:** HIGH — documented in OpenAI security model with cross-referenced platform details.

---

## 3. Codex Project Context Discovery (AGENTS.md, CLAUDE.md, config.toml)

### Context Loading Hierarchy

Codex automatically discovers and reads project instructions following a **three-tier precedence system**:

#### Tier 1: Global Scope
```
1. ~/.codex/AGENTS.override.md      (if exists, overrides all)
2. ~/.codex/AGENTS.md               (if exists)
```

#### Tier 2: Project Scope (Walks from git root to current directory)
For each directory:
```
1. AGENTS.override.md               (local override)
2. AGENTS.md                        (standard file)
3. [project_doc_fallback_filenames]  (e.g., CLAUDE.md, TEAM_GUIDE.md)
```

#### Tier 3: Merge Order
- Files concatenate **root-down** with blank-line separators
- Files **closer to current directory override** earlier guidance
- Maximum total read: `project_doc_max_bytes` (default 32 KB)

### Discovery Mechanism Example

For `gsd-multi-model`:

```
~/.codex/AGENTS.md                  (loaded first if exists)
.git/                               (git root marker)
/home/agent/gsd-multi-model/AGENTS.md      (project root)
/home/agent/gsd-multi-model/.planning/AGENTS.md (if exists, overrides root)
```

Codex stops reading once 32 KB is reached.

### Configuration: `~/.codex/config.toml`

```toml
[settings]
model = "gpt-5.3-codex"
approval_policy = "on-request"
sandbox_mode = "workspace-write"

# CRITICAL for gsd-multi-model:
project_doc_max_bytes = 32768
project_doc_fallback_filenames = ["CLAUDE.md", "COPILOT.md", "TEAM_GUIDE.md"]

[profiles.full-auto]
model = "gpt-5.3-codex"
approval_policy = "never"
sandbox_mode = "workspace-write"

[profiles.read-only]
sandbox_mode = "read-only"
approval_policy = "on-request"
```

### How to Verify Context Loading

```bash
# Test: see which instruction files Codex loaded
codex exec --ask-for-approval never "Summarize the current instructions loaded from AGENTS.md files"

# Should list the full instruction chain in precedence order
```

### Integration with gsd-multi-model Spec

**Current setup in SPEC.md:**
```toml
# ~/.codex/config.toml
project_doc_fallback_filenames = ["CLAUDE.md", "AGENTS.md", "COPILOT.md"]
```

This is correct — Codex will read:
1. `~/.codex/AGENTS.md` (global)
2. Project-level `AGENTS.md` (project conventions)
3. Project-level `CLAUDE.md` (Claude-specific that Codex also reads as fallback)

**Recommendation:** Ensure `.planning/AGENTS.md` does NOT exist (or is identical to root), since `.planning/` is protected from Codex writes anyway.

### Automatic File Skipping

Codex automatically ignores:
- Empty files (zero bytes)
- Files above 32 KB (stops concatenation)
- Files in protected directories (`.git`, `.agents`, `.codex`)

**Confidence:** HIGH — documented in official Codex guides with tested discovery patterns.

---

## 4. Git Worktree Patterns for Parallel Codex Execution

### Why Worktrees Are Essential

Git enforces **one-branch-per-worktree rule** — each worktree has independent branches but shares the same `.git` metadata. This allows:

- Multiple Codex agents coding simultaneously on different branches
- Zero git conflicts (branches are isolated)
- Simple merge strategy (each worktree = one feature branch)
- Parallel execution multiplier for autonomous tasks

### Parallel Execution Pattern

```bash
# Main worktree: Claude Code (interactive, complex work)
cd /home/agent/gsd-multi-model
claude
# → /gsd:execute-phase on complex tasks

# Terminal 2: Codex agent 1 (autonomous task A)
git worktree add ../task-a task-a-branch
cd ../task-a
codex exec --full-auto "Implement task A: API endpoints per .planning/PLAN.md" &

# Terminal 3: Codex agent 2 (autonomous task B)
git worktree add ../task-b task-b-branch
cd ../task-b
codex exec --full-auto "Implement task B: test suite per .planning/PLAN.md" &

# Terminal 4: Codex agent 3 (autonomous task C)
git worktree add ../task-c task-c-branch
cd ../task-c
codex exec --full-auto "Implement task C: CI/CD pipeline per .planning/PLAN.md" &

# Wait for all agents to finish
wait

# Merge worktrees back:
git worktree remove ../task-a
git worktree remove ../task-b
git worktree remove ../task-c
git merge task-a-branch
git merge task-b-branch
git merge task-c-branch
```

### Best Practices for Parallel Codex

1. **Assign one task per worktree** — Codex's autonomy works best with a single, well-scoped task per run
2. **Use semantic branch names** — `task-auth`, `task-tests`, `task-ci` make it clear what each Codex agent is doing
3. **Capture output for later review** — Use `--json` or `-o` to save results to files for audit
4. **Respect dependencies** — If task B depends on task A, run A first, merge, then run B
5. **Set working directory explicitly** — Use `--cd /path/to/worktree` in scripts to avoid confusion
6. **Clean up worktrees after merge** — `git worktree remove <path>` when done

### Worktree Workflow in gsd-multi-model

```bash
#!/bin/bash
# Execute parallel Codex tasks from .planning/PLAN.md

PLAN_FILE=".planning/milestones/m1/phase3-PLAN.md"
CODEX_TASKS=(
  "task-endpoints:Implement REST API endpoints per PLAN.md section 3.1"
  "task-tests:Write test suite for API endpoints per PLAN.md section 3.2"
  "task-ci:Set up GitHub Actions pipeline per PLAN.md section 3.3"
)

for task_def in "${CODEX_TASKS[@]}"; do
  IFS=: read -r BRANCH_NAME TASK_PROMPT <<< "$task_def"

  # Create worktree
  git worktree add ../$BRANCH_NAME $BRANCH_NAME

  # Run Codex in parallel
  (
    cd ../$BRANCH_NAME
    codex exec \
      --full-auto \
      --json \
      --ephemeral \
      -o "/tmp/$BRANCH_NAME-result.jsonl" \
      "$TASK_PROMPT"
  ) &
done

wait
echo "All Codex agents completed"

# Merge results (assuming no conflicts due to task isolation)
for task_def in "${CODEX_TASKS[@]}"; do
  IFS=: read -r BRANCH_NAME _ <<< "$task_def"
  git merge $BRANCH_NAME
  git worktree remove ../$BRANCH_NAME
done
```

### Key Constraint

**One branch per worktree:** If you create `feature/auth` in a worktree, you cannot check out `feature/auth` in your main checkout or another worktree simultaneously.

**Implication:** Always use unique branch names. Use semantic naming (`gsd/phase-{n}/task-{name}`) to avoid collisions.

**Confidence:** HIGH — tested patterns from official Codex docs and real-world GSD workflows.

---

## 5. Codex Output Capture & Result Verification Patterns

### Output Modes

#### Mode 1: Interactive TUI (Default)
```bash
codex "Implement the auth module"
# → Full terminal UI with real-time progress
# → User approves actions before execution
# → Session saved to ~/.codex/sessions/YYYY/MM/DD/
```

**Result:** Manual review, best for exploratory work.

#### Mode 2: Non-Interactive (codex exec)
```bash
codex exec "Implement the auth module"
# → Streams progress to stderr
# → Prints final agent message to stdout
# → Can be piped to other tools
# → Default: read-only sandbox
```

**Result:** Simple text output, good for CLI chaining.

#### Mode 3: JSON Streaming (JSONL)
```bash
codex exec --json "task" | tee /tmp/codex-events.jsonl
```

**Output:** JSONL (one JSON object per line) with event types:
- `thread.started` — Session initialized
- `turn.started` — Agent starting a turn
- `turn.completed` — Agent finished with result
- `turn.failed` — Agent encountered error
- `item.message` — Agent message (reasoning, responses)
- `item.command` — Shell command executed
- `item.file_read` — File read operation
- `item.file_write` — File write operation
- `item.plan` — Plan updates
- `error` — Execution error

**Example JSONL event:**
```json
{"type":"turn.completed","timestamp":"2026-03-02T10:45:23Z","agent":"codex-gpt5.3","status":"success","changes":3}
{"type":"item.file_write","path":"src/auth.ts","lines":127}
```

#### Mode 4: Structured Output with Schema
```bash
codex exec \
  --output-schema schema.json \
  -o result.json \
  "Analyze this repo and return findings in the specified schema"
```

**Input:** `schema.json` (JSON Schema defining expected output format)
**Output:** `result.json` (Codex's final response validated against schema)

**Example schema:**
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "summary": { "type": "string" },
    "files_modified": { "type": "integer" },
    "issues": {
      "type": "array",
      "items": { "type": "string" }
    }
  }
}
```

### Result Verification Patterns

#### Pattern 1: Git Status Verification
```bash
# After Codex finishes, check what changed
git status
git diff --stat HEAD~1..HEAD

# Verify no protected files were modified
git diff --name-only HEAD~1..HEAD | grep -E "^\.git|^\.codex|^\.planning" && echo "ERROR: Protected files modified!" || echo "OK"
```

#### Pattern 2: Parse JSONL for Errors
```bash
#!/bin/bash
# Extract error events from JSONL output

RESULT_FILE="/tmp/codex-result.jsonl"
ERRORS=$(jq -r 'select(.type=="error") | .message' "$RESULT_FILE" | wc -l)

if [ "$ERRORS" -gt 0 ]; then
  echo "Codex encountered $ERRORS errors:"
  jq -r 'select(.type=="error") | .message' "$RESULT_FILE"
  exit 1
fi

# Extract change count
CHANGES=$(jq -r 'select(.type=="turn.completed") | .changes' "$RESULT_FILE" | tail -1)
echo "Codex completed with $CHANGES changes"
```

#### Pattern 3: Validate Against Expected Changes
```bash
# Verify Codex only modified files mentioned in PLAN.md

MODIFIED_FILES=$(git diff --name-only HEAD~1..HEAD)
EXPECTED_FILES=$(grep -o "src/[^ ]*\|tests/[^ ]*" .planning/PLAN.md | sort -u)

for file in $MODIFIED_FILES; do
  if ! echo "$EXPECTED_FILES" | grep -q "^$file$"; then
    echo "WARNING: Unexpected file modified: $file"
  fi
done
```

#### Pattern 4: Test Execution Verification
```bash
#!/bin/bash
# Run tests after Codex execution to verify quality

codex exec --full-auto "Implement API endpoints and tests per PLAN.md"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
  echo "Codex execution failed"
  exit 1
fi

# Run test suite
npm test
if [ $? -ne 0 ]; then
  echo "Tests failed — Codex output may have issues"
  git show HEAD --stat  # Show what Codex changed
  exit 1
fi

echo "Codex execution + tests passed"
```

### Session Transcripts & Rollback

**Codex always saves transcripts:**
```
~/.codex/sessions/2026/03/02/rollout-*.jsonl
```

**Recover a session:**
```bash
codex resume          # List recent sessions
codex resume <id>     # Resume a previous session
```

**Rollback Codex changes:**
```bash
# Since each Codex task = atomic commit, revert is simple:
git log --oneline | head -5
# Copy the commit hash before Codex's work
git reset --hard <hash>
```

### Recommended Verification Workflow for gsd-multi-model

```bash
#!/bin/bash
# After Codex finishes, verify before merging

TASK_BRANCH="task-api"
RESULT_FILE="/tmp/codex-result.jsonl"

# 1. Verify no errors in JSONL
if jq -e '.[] | select(.type=="error")' "$RESULT_FILE" > /dev/null 2>&1; then
  echo "ERROR: Codex encountered errors"
  jq -r 'select(.type=="error") | .message' "$RESULT_FILE"
  exit 1
fi

# 2. Verify no protected files modified
PROTECTED=$(git diff main..$TASK_BRANCH --name-only | grep -E "^\.planning|^\.git|^\.codex")
if [ -n "$PROTECTED" ]; then
  echo "ERROR: Protected files modified by Codex"
  echo "$PROTECTED"
  exit 1
fi

# 3. Run tests
npm test || exit 1

# 4. Lint
npm run lint || exit 1

# 5. If all pass, ready for human review
echo "✓ Codex output verified — ready for human review"
git log --oneline main..$TASK_BRANCH
```

**Confidence:** HIGH — documented JSONL output format, real transcript storage, tested verification patterns.

---

## 6. Codex Limitations: What It Handles Well vs Poorly

### Strengths (What Codex Excels At)

| Task Type | Why Codex Wins | Confidence |
|-----------|----------------|------------|
| **CRUD Endpoints** | Well-defined, boilerplate-heavy, predictable patterns | HIGH |
| **Test Writing** | Follows templates, exhaustive coverage, no design tradeoffs | HIGH |
| **CLI Tools & Scripts** | Terminal-native, direct execution feedback, quick iteration | HIGH |
| **Bug Fixes (with clear repro)** | Reproducer provides context, fix is mechanical | MEDIUM |
| **CI/CD Pipelines** | Templated (GitHub Actions, CircleCI), stable syntax | HIGH |
| **Refactoring Well-Defined Modules** | Mechanical token-replacement, tests verify correctness | MEDIUM |
| **Code Review of Autonomous Tasks** | Different model perspective catches blind spots | HIGH |

### Weaknesses (Known Limitations)

| Limitation | Symptom | Mitigation |
|------------|---------|-----------|
| **Connection Stability (v0.87.0)** | "Re-connecting" loops, 401 errors, credential conflicts | Update to latest, verify `~/.codex/auth.json` vs CODEX_API_KEY, restart CLI |
| **Rate Limiting** | Hits usage limits after 1–2 large requests on big projects | Use `codex-sparse` mode, smaller task scopes, batch efficiently |
| **Context Degradation (Long Conversations)** | Model quality decreases after 10+ turns; recursive compaction bugs | Use `codex exec` (fresh context per run), avoid resuming very old sessions |
| **Large Codebase Analysis** | Struggles with repos >10K LOC analyzed at once | Break into smaller analysis tasks, focus on specific modules |
| **MCP/Tool Integration** | SSE/HTTP2 handshake failures, OAuth issues; inconsistent behavior | Update Rust MCP client, simplify tool specs, test tooling separately |
| **Multi-File Refactoring** | Can miss cross-file dependencies, rename inconsistencies | Verify manually, use test suite as validation |
| **Ambiguous Specifications** | If task description is vague, output is unpredictable | Write detailed task specs in .planning/PLAN.md |
| **Environment/Permission Issues** | File access errors, missing dev tools, permission denied | Ensure Codex has read/write to workspace, install required tooling |

### When to Use Claude Code Instead

| Situation | Why Claude Code is Better |
|-----------|--------------------------|
| **Multi-file architecture changes** | Interactive reasoning about complex tradeoffs |
| **Design-sensitive features** | Can discuss UX, accessibility, performance implications |
| **Ambiguous requirements** | Can ask clarifying questions and iterate with you |
| **Exploring new tech** | Can research, test hypotheses, adapt approach |
| **Handling failures** | Can debug, understand why something failed, adjust strategy |
| **Abstract refactoring** | Understands intent beyond mechanical token-swapping |

### Hybrid Approach Recommendation for gsd-multi-model

```
┌─────────────────────┐
│ GSD PLAN            │
├─────────────────────┤
│ Task 1: Refactor    │ → Claude Code (interactive, multi-file awareness)
│ Task 2: Add tests   │ → Codex (autonomous, template-based)
│ Task 3: Fix bug     │ → Codex (clear repro, mechanical fix)
│ Task 4: API design  │ → Claude Code (requires design reasoning)
│ Task 5: Implement   │ → Codex (well-defined endpoints, CRUD)
│ Task 6: CI/CD       │ → Codex (templated, isolated from product code)
└─────────────────────┘

Verification:
- Codex output reviewed by Claude (different model perspective)
- Claude output reviewed by Codex (catches edge cases)
- Both must pass test suite before advancing
```

### Critical Codex Failure Case: The "Ambiguous Task" Trap

**What happens:**
```
# Bad prompt (too vague)
codex "Improve the authentication system"

# Codex doesn't know what "improve" means
# May refactor unnecessarily, miss actual security issues, or break existing flow
```

**Prevention:**
```bash
# Good prompt (concrete, from PLAN.md)
codex exec --full-auto "Implement JWT token refresh per .planning/PLAN.md section 2.3:
- Add POST /auth/refresh endpoint
- Return { access_token, refresh_token, expires_in }
- Validate refresh token against DB
- Return 401 if expired
- Cover edge cases per PLAN.md test matrix"
```

**Implication for gsd-multi-model:** Always generate Codex tasks from GSD PLAN.md (which is detailed by design), never free-form prompts.

**Confidence:** HIGH — documented limitations from OpenAI, real user reports, and integration patterns.

---

## 7. Integration Strategy for gsd-multi-model

### Recommended Workflow

#### Phase 3: Execute (Dual-Coder)

```bash
# 1. From Claude Code, generate detailed PLAN
/gsd:plan-phase
# → Creates .planning/milestones/m1/phase3-PLAN.md with concrete tasks

# 2. Identify autonomous vs complex tasks (already tagged in PLAN)
# - Autonomous: CRUD, tests, scripts, CI/CD, clear bug fixes
# - Complex: architecture, design, multi-file refactoring, exploration

# 3. Create worktrees for parallel execution
git worktree add ../task-autonomous task-autonomous-branch
git worktree add ../task-complex task-complex-branch

# 4. Terminal 1: Claude handles complex work (interactive)
cd task-complex && claude
# → /gsd:execute-phase on complex tasks

# 5. Terminal 2: Codex handles autonomous tasks (fire-and-forget)
cd ../task-autonomous
codex exec \
  --full-auto \
  --json \
  --ephemeral \
  -o /tmp/codex-result.jsonl \
  "Implement all autonomous tasks per .planning/milestones/m1/phase3-PLAN.md:

   Tasks to implement:
   - $(grep '^\- \[.*\] Autonomous' .planning/milestones/m1/phase3-PLAN.md | sed 's/- \[.*\] //')

   Reference:
   - Requirements: .planning/REQUIREMENTS.md
   - Architecture: AGENTS.md
   - This project uses GSD + dual-coder workflow (see CLAUDE.md for context)"

# 6. After Codex finishes, verify output
if jq -e '.[] | select(.type=="error")' /tmp/codex-result.jsonl > /dev/null; then
  echo "Codex errors detected"
  git reset --hard main
  exit 1
fi

# 7. Run test suite
npm test || { git reset --hard main; exit 1; }

# 8. Merge both worktrees back
git merge task-complex-branch
git merge task-autonomous-branch
```

#### Phase 4: Verify (Cross-Review)

```bash
# Use the combined verification skill
/gsd-codex-verify

# This runs:
# 1. GSD verifier: checks all changes against .planning/REQUIREMENTS.md
# 2. Codex reviewer: cross-model review of all code
# 3. Combined report with CRITICAL/WARNING/INFO findings
```

### Critical Integration Points

1. **AGENTS.md is the shared instruction source**
   - Both Claude and Codex read this for project conventions
   - Keep it concise (<32 KB) and actionable

2. **.planning/ is protected from Codex modification**
   - GSD state files cannot be accidentally corrupted
   - Codex cannot break the workflow

3. **Codex tasks must be derived from GSD PLAN.md**
   - Never free-form prompts
   - Always cite PLAN.md section numbers in task descriptions

4. **Verification happens after both tools finish**
   - Not before merging
   - Use `--json` output for automated checks
   - Human review for anything Codex-modified

5. **Parallel execution requires semantic branch names**
   - `gsd/phase-3/task-api`, `gsd/phase-3/task-tests`, etc.
   - Makes it clear what each Codex agent did

---

## 8. Risk Assessment & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| **Codex modifies .planning/ files** | LOW | CRITICAL | Protected by sandbox; verify with `git diff HEAD~1 --name-only \| grep .planning` |
| **Ambiguous task → unexpected behavior** | MEDIUM | MEDIUM | Always task from PLAN.md; detailed specs in PLAN entries |
| **Large repo hits rate limits** | MEDIUM | LOW | Use `codex-sparse` mode, smaller task scopes, batch tasks |
| **Connection instability during execution** | MEDIUM | MEDIUM | Use `--ephemeral`, don't rely on resuming; retry with fresh context |
| **Codex misses cross-file dependencies** | MEDIUM | HIGH | Run full test suite after Codex execution; use Claude for verification |
| **Output doesn't match expected schema** | LOW | MEDIUM | Use `--output-schema` with JSON Schema validation |
| **Git conflicts when merging worktrees** | LOW | MEDIUM | Ensure task isolation (different files), use semantic branch names |

---

## 9. Confidence Summary

| Area | Confidence | Why | Validation |
|------|------------|-----|-----------|
| **Codex CLI Flags** | HIGH | Official OpenAI CLI reference + real usage patterns | Docs + multiple sources agree |
| **Sandbox & Security** | HIGH | Official security model with OS-specific details | OpenAI security docs + platform implementations |
| **AGENTS.md Discovery** | HIGH | Documented with examples and troubleshooting | Official context guide + verified patterns |
| **Worktree Parallel Execution** | HIGH | Tested patterns from official docs + community | Multiple sources confirm constraint (one branch per worktree) |
| **Output Capture (JSON/JSONL)** | HIGH | Official JSONL event types documented | Docs specify event types and formats |
| **Limitations & Failures** | MEDIUM-HIGH | User reports + OpenAI changelog notes | Some limitations from community discussion, others from official release notes |
| **Integration Patterns** | HIGH | Aligned with SPEC.md existing patterns | Spec already assumes Codex fire-and-forget, just verified details |

---

## 10. Open Questions / Needed Validation

1. **Rate limiting thresholds** — What exactly triggers rate limits on gsd-multi-model? Need to test with real PLAN.md sizes
2. **MCP tool stability** — How stable are custom MCP tools in parallel Codex agents? May need fallback for complex tooling
3. **Transcript recovery in CI** — Does `codex resume` work well in CI? May need special handling for ephemeral runs
4. **Large .planning/ files** — If .planning/PLAN.md exceeds 32 KB, will Codex truncate context? May need to split large plans
5. **Credential handling in CI** — Best practice for CODEX_API_KEY in GitHub Actions? (env var vs secrets.CODEX_KEY?)

---

## 11. Recommended Next Steps

### For gsd-multi-model Implementation:

1. **Update SPEC.md** with Codex command examples from this research (sections 6.3–6.4)

2. **Add to ~/.codex/config.toml:**
   ```toml
   [profiles.gsd-full-auto]
   model = "gpt-5.3-codex"
   approval_policy = "never"
   sandbox_mode = "workspace-write"
   project_doc_fallback_filenames = ["CLAUDE.md", "AGENTS.md", "COPILOT.md"]
   ```

3. **Create a Codex execution helper script** (`bin/codex-task.sh`):
   ```bash
   #!/bin/bash
   # Wrapper for safe Codex execution with verification
   # Usage: ./bin/codex-task.sh "task description from PLAN.md"
   # Output: verified JSON result
   ```

4. **Enhance /gsd-codex-verify skill** with:
   - Automatic protected-file verification
   - JSONL parse for errors
   - Test execution before declaring success

5. **Test parallel Codex execution** with a real phase 3 plan
   - Create 3+ semantic branch worktrees
   - Run Codex agents simultaneously
   - Merge and verify no conflicts

---

## Sources

- [OpenAI Codex CLI Reference](https://developers.openai.com/codex/cli/reference/)
- [Codex CLI Features](https://developers.openai.com/codex/cli/features/)
- [Codex Security Model](https://developers.openai.com/codex/security)
- [Codex Advanced Configuration](https://developers.openai.com/codex/config-advanced/)
- [Codex AGENTS.md Guide](https://developers.openai.com/codex/guides/agents-md/)
- [Codex Non-Interactive Mode](https://developers.openai.com/codex/noninteractive/)
- [Git Worktrees for Parallel AI Execution](https://developers.openai.com/codex/app/worktrees/)
- [Codex Changelog (2026)](https://developers.openai.com/codex/changelog/)
- [Community Worktree Patterns](https://github.com/johannesjo/parallel-code)
