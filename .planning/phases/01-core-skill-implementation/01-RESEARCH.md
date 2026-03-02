# Phase 1: Core Skill Implementation - Research

**Researched:** 2026-03-02
**Domain:** Claude Code skill development, Codex CLI integration, Bash subprocess orchestration
**Confidence:** HIGH

## Summary

This phase requires implementing three production-grade Claude Code skills that orchestrate the dual-tool GSD workflow. Each skill is prompt-based (not custom code), using YAML frontmatter and Bash/Read/Write/Glob/Grep tools to integrate with Codex CLI, GSD state files, and git operations. All three skills already have detailed step-by-step instructions in their SKILL.md files — this phase refines those into working implementations with proper error handling, idempotency, and Codex invocation patterns.

The key technical challenge is reliable Codex invocation via `codex exec` with `--full-auto --json` flags, JSONL event parsing for structured output, and graceful fallback when Codex is unavailable. All three skills must handle realistic failure modes (missing deps, API timeouts, conflicting configs) and never leave projects in broken states.

**Primary recommendation:** Build skills in this order: (1) `/init-gsd` (foundation for other two), (2) `/codex-review` (simpler Codex integration), (3) `/gsd-codex-verify` (combines both). Each skill is prompt-based with allowed tools restricted to safe operations; idempotency and error messages are critical.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Codex Invocation Method:**
- Use `codex exec --full-auto` for all automated Codex calls (non-interactive, fire-and-forget)
- `/gsd-codex-verify` uses `--json` flag for structured JSONL parsing (pass/fail detection)
- `/codex-review` uses plain text stdout for human-readable display
- Timeout configurable via `.planning/config.json` with `codex.timeout_seconds` key, default 5 minutes
- When Codex CLI not installed or API key missing: graceful skip with warning, GSD verification runs solo

**Skill Completeness:**
- Quality bar: PRODUCTION-GRADE — handle all realistic failure modes (missing deps, partial installs, network timeouts, conflicting configs, interrupted runs)
- Clear error recovery for each failure mode — skills should never leave things in broken state
- No silent failures — every error path produces actionable message
- `/init-gsd` auto-chains to `/gsd:new-project` with user prompt ("Run /gsd:new-project now?")
- `/codex-review` diff scope: last N commits (default 5), user can pass `--commits=N` to adjust
- `/gsd-codex-verify` writes VERIFICATION.md AND displays results inline (both)

**Idempotency & Existing Projects:**
- `/init-gsd` default: skip existing files, create missing ones — never overwrite user customizations
- Support `--force` flag to overwrite everything when user explicitly wants to reset
- Stack detection: read package.json / pyproject.toml / Makefile to fill in Build & Test commands in AGENTS.md
- Scope: create both project-local files AND global configs (Codex config.toml, ~/.claude/CLAUDE.md) if missing
- Print summary showing what was created vs skipped

**Output & Result Formatting:**
- Codex review findings displayed as structured report blocks with severity levels (CRITICAL/WARNING/INFO)
- Use the `═══` border format from spec for combined verification reports
- On FAIL: report only — show what failed, user decides next action (no auto-generated fix tasks)
- Raw Codex output in appendix: Claude's discretion based on output length and relevance

### Claude's Discretion

- Exact error message wording
- How to handle partial Codex responses (timeout mid-review)
- Whether to retry Codex on transient failures or fail immediately
- Stack detection depth (how many config files to check)

### Deferred Ideas (OUT OF SCOPE)

- None — discussion stayed within phase scope

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| R1 | `/init-gsd` must bootstrap any new project from within Claude Code; creates AGENTS.md, CLAUDE.md, .claude/rules/, git init, .planning/ scaffold; must be idempotent (safe to re-run); reads project directory to detect existing stack/framework | **Stack Detection Pattern:** Read package.json (Node), pyproject.toml (Python), Makefile (any) to populate Build & Test commands; skip existing files unless --force; **Idempotency:** Check for existing .planning/, AGENTS.md before creating; **Output:** Summary showing created vs skipped files; **Tool Strategy:** Read (detect), Write (create files), Bash (git init, npm/pip detection) |
| R2 | `/codex-review` invokes `codex exec` to review Claude's changes; accepts optional focus area parameter; captures Codex output and presents findings inline | **Codex Invocation:** `codex exec --full-auto "review prompt..."` with plain text stdout; **Scope Control:** Git diff last N commits (default 5, customizable via --commits=N); **Output:** Structured report with CRITICAL/WARNING/INFO severity levels; **Tool Strategy:** Read (STATE.md, REQUIREMENTS.md), Bash (git diff, codex exec), Glob/Grep (identify file changes) |
| R3 | `/gsd-codex-verify` runs GSD verifier then Codex cross-review; produces structured PASS/FAIL report; checks both structural compliance and code quality | **Dual Review:** Run /gsd:verify-work first (check REQUIREMENTS conformance), then `codex exec --full-auto --json` for JSONL parsing; **Output:** VERIFICATION.md file + inline display with ═══ borders; **JSONL Parsing:** Listen for turn.completed, error events to detect pass/fail; **Tool Strategy:** Read (all phase files), Write (VERIFICATION.md), Bash (codex exec with JSON parsing) |
| R4-R9 | Out of scope for Phase 1 (deferred to Phase 2+) | Phase 1 focuses only on R1-R3 skill implementations |

</phase_requirements>

## Standard Stack

### Core: Claude Code Skill Development

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Claude Code | Latest (Opus 4.6+) | Skill orchestration platform | Standard for prompt-based extensions |
| SKILL.md format | Agent Skills standard | Skill packaging and metadata | Cross-tool compatible (Claude Code, Codex, Gemini) |
| `disable-model-invocation: true` | YAML frontmatter | Manual-only invocation control | Prevents unwanted auto-triggering of side-effect skills |
| `allowed-tools` constraint | YAML frontmatter | Tool access gating | Restricts skills to safe operations (no Bash unless needed) |

### Dependencies: Codex CLI Integration

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Codex CLI | Latest (2026.03+) | Autonomous code agent | Cross-model review; `codex exec --full-auto --json` for automation |
| GSD Framework | Latest (get-shit-done-cc) | Planning/verification scaffolding | State management; structured specs in .planning/ |
| Node.js | 18+ | Script execution (for CLI helpers) | Optional — skills use Bash primarily |
| jq | Latest | JSONL/JSON parsing from shell | Optional — for parsing `codex exec --json` output |

### Supported Configuration

| File | Location | Purpose | Scope |
|------|----------|---------|-------|
| config.json | `.planning/config.json` | GSD workflow config (codex.timeout_seconds) | Project-local |
| config.toml | `~/.codex/config.toml` | Codex CLI settings (model, approval_policy, sandbox) | Global (installed by init.sh) |
| AGENTS.md | Project root | Build/test commands, conventions | Shared between Claude + Codex |
| CLAUDE.md | Project root | Claude-specific workflow | Claude-only |

## Architecture Patterns

### Pattern 1: Skill as Orchestrator

**What:** Skills are prompt-based (SKILL.md is the implementation), using allowed tools to orchestrate work. Not building custom Node.js code — instructions + tool calls.

**When to use:** All three skills (`/init-gsd`, `/codex-review`, `/gsd-codex-verify`) follow this pattern.

**Example:**
```yaml
---
name: init-gsd
description: Bootstrap a new GSD + Codex project
disable-model-invocation: true
allowed-tools: Read, Write, Bash, Glob
---

Your step-by-step instructions here. Claude reads this, then executes via allowed tools.
```

**Source:** [Claude Code Skills Documentation - Extend Claude with Skills](https://code.claude.com/docs/en/skills)

### Pattern 2: Graceful Codex Invocation with Fallback

**What:** Detect if Codex CLI is available; if not, skip that step with a warning but continue. Never fail the entire skill if Codex is missing.

**When to use:** Both `/codex-review` and `/gsd-codex-verify` must support this.

**Example pattern:**
```bash
if command -v codex >/dev/null 2>&1; then
  # Codex is available, run the review
  codex exec --full-auto "your prompt..."
else
  # Codex not available — skip gracefully
  echo "⚠ Codex CLI not installed. Skipping cross-model review."
  echo "  (GSD verification will still run solo)"
fi
```

**Key insight:** Codex is a "nice-to-have" for cross-review, not a blocker. GSD verification is always available.

### Pattern 3: JSONL Event Parsing for Structured Output

**What:** When `codex exec --json` is used, stdout becomes a stream of newline-delimited JSON events (JSONL). Parse these to detect pass/fail status and extract specific findings.

**When to use:** `/gsd-codex-verify` only (uses `--json` flag).

**Event types from Codex:**
- `turn.completed` — Codex finished a turn, has output
- `error` — Something failed
- `item.file_write` — File was modified
- `turn.started` — Turn started

**Example pattern (Bash with jq):**
```bash
codex exec --full-auto --json "review prompt..." | while IFS= read -r line; do
  if echo "$line" | jq -e '.type == "error"' >/dev/null 2>&1; then
    echo "ERROR: $(echo "$line" | jq -r '.message')"
    exit 1
  fi
  if echo "$line" | jq -e '.type == "turn.completed"' >/dev/null 2>&1; then
    echo "$(echo "$line" | jq -r '.message')"
  fi
done
```

**Source:** [Codex CLI Reference - Command-line options](https://developers.openai.com/codex/cli/reference/); [JSON Lines format](https://jsonlines.org/)

### Pattern 4: Idempotent State Management

**What:** Skills check current state before taking action. Safe to re-run without breaking existing customizations.

**When to use:** `/init-gsd` must be idempotent.

**Checks to perform:**
1. Does `.planning/` exist? → Skip GSD init if present
2. Does `AGENTS.md` exist? → Skip (unless --force flag)
3. Does `.claude/rules/` exist? → Skip existing rule files
4. Does `~/.claude/CLAUDE.md` exist? → Append GSD section only if missing

**Pattern:**
```bash
if [ -f "AGENTS.md" ] && [ "$FORCE" != "true" ]; then
  echo "AGENTS.md exists, skipping (use --force to overwrite)"
else
  # Create or overwrite AGENTS.md
fi
```

**Key insight:** Never silently skip; always report what was created vs skipped.

### Anti-Patterns to Avoid

- **Silent failures:** Every error (missing Codex, network timeout, broken config) must produce an actionable message
- **Overwriting customizations:** `/init-gsd` should NEVER overwrite user-edited AGENTS.md without explicit --force flag
- **Requiring Codex:** Skills must work without Codex CLI installed; it's optional infrastructure
- **Blocking on timeouts:** If `codex exec` times out, report it but don't break the entire verification flow

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Reading GSD state | Custom JSON parsing | Read tool + direct file access | GSD files are simple YAML/Markdown; no parser needed |
| Git operations (diff, branch, merge) | Home-grown git commands | Bash with `git` CLI directly | Git is complex; use native CLI which handles edge cases |
| Codex invocation | Custom subprocess management | `codex exec` CLI directly | Codex handles auth, sandbox, error reporting; shell out to it |
| JSONL parsing from Codex | Complex streaming parser | `jq` CLI (already standard) | jq is battle-tested for JSON filtering; leverage it |
| File template generation | String concatenation | Here-docs + Write tool | Clean, readable, easy to debug |

**Key insight:** Skills are orchestration + judgment, not heavy lifting. Delegate to standard tools (git, jq, codex, bash).

## Common Pitfalls

### Pitfall 1: Assuming Codex CLI is Always Available

**What goes wrong:** Skill crashes with "codex: command not found" when Codex is not installed or API key is missing.

**Why it happens:** Codex is optional third-party infrastructure; many users won't have it set up.

**How to avoid:**
1. Check `command -v codex` before any `codex exec` call
2. If missing, print clear message: "Codex CLI not installed. Skipping cross-review. (To install: npm install -g codex-cli)"
3. Continue with the rest of the skill

**Warning signs:** Skills that don't mention Codex availability or have no fallback path.

### Pitfall 2: Over-Complicating Idempotency Logic

**What goes wrong:** `/init-gsd` creates a broken partial state when re-run on existing project. E.g., deletes old AGENTS.md then fails to create new one.

**Why it happens:** Not checking for existing files before writing; destructive operations without rollback.

**How to avoid:**
1. Check before every Write: "Does this file exist? If yes, skip (unless --force)"
2. Print summary at end: "Created: X, Skipped: Y, Updated: Z"
3. Never delete and recreate — just check and conditionally write

**Warning signs:** Skills that modify ~/.claude/ or .planning/ without confirming user intent.

### Pitfall 3: Silent Timeout When Codex is Slow

**What goes wrong:** `codex exec` times out mid-review; user sees no output and assumes the skill hung.

**Why it happens:** Codex can take 30+ seconds on large codebases; no progress reporting from long-running subprocess.

**How to avoid:**
1. Set explicit timeout via `codex.timeout_seconds` in config (default 5 minutes)
2. Capture both stdout and exit code from `codex exec`
3. If timeout, report: "Codex review timed out after 5m. (Increase codex.timeout_seconds in .planning/config.json)"
4. Always show *something* to the user (progress indicator, partial results)

**Warning signs:** Skills with unbounded subprocess calls and no error handling.

### Pitfall 4: Forgetting to Write VERIFICATION.md

**What goes wrong:** `/gsd-codex-verify` displays inline results but doesn't persist them to file. User can't reference results later.

**Why it happens:** Focused on success path (displaying results) and forgot the spec requires file persistence.

**How to avoid:**
1. Always Write VERIFICATION.md after collecting results
2. Include both: inline display + file persist
3. Reference the file path in inline output: "Full report: .planning/phases/XX-YY/YY-VERIFICATION.md"

**Warning signs:** Specs that say "write VERIFICATION.md" but implementation only prints to stdout.

### Pitfall 5: Not Handling Partial Codex Output

**What goes wrong:** `codex exec --json` fails mid-stream (network interrupt, API error). Skill crashes trying to parse truncated JSON.

**Why it happens:** JSONL parser assumes all events complete cleanly; doesn't handle EOF or malformed lines gracefully.

**How to avoid:**
1. Use `jq` with error handling: `jq -e 'select(.type == "error")' 2>/dev/null || true`
2. If parsing fails, log the raw line and continue (don't exit)
3. At the end, check if we got a "turn.completed" event; if not, report "Incomplete Codex output"

**Warning signs:** Skills using `jq` without `2>/dev/null` error suppression.

## Code Examples

Verified patterns from official sources:

### Example 1: Skill Frontmatter and Tool Restrictions

```yaml
---
name: init-gsd
description: Bootstrap a new project with GSD + Codex workflow
disable-model-invocation: true
argument-hint: [project-name]
allowed-tools: Read, Write, Bash, Glob
---

# Your skill instructions here...
```

**Source:** [Claude Code Skills Documentation - Frontmatter Reference](https://code.claude.com/docs/en/skills)

**Why this matters:** `disable-model-invocation: true` prevents Claude from auto-triggering this side-effect skill. `allowed-tools` restricts to safe operations (no Bash unless safe).

### Example 2: Graceful Codex Availability Check

```bash
# Check if Codex is available
if ! command -v codex >/dev/null 2>&1; then
  echo "⚠ Codex CLI not installed. Skipping cross-model review."
  echo "  Install with: npm install -g codex-cli"
  echo "  GSD verification will run solo."
  exit 0  # Not a failure — continue
fi

# Codex is available, proceed with invocation
codex exec --full-auto "Review this project against REQUIREMENTS.md..."
```

**Source:** [Bash command substitution](https://www.gnu.org/software/bash/manual/html_node/Command-Substitution.html); [Codex CLI](https://developers.openai.com/codex/cli/)

### Example 3: JSONL Parsing with jq (from Codex --json output)

```bash
# Run Codex with --json to get JSONL stream
codex exec --full-auto --json "Review for bugs..." | {
  has_error=false
  while IFS= read -r line; do
    # Check for errors
    if echo "$line" | jq -e '.type == "error"' >/dev/null 2>&1; then
      has_error=true
      echo "ERROR: $(echo "$line" | jq -r '.message')"
    fi
    # Collect findings
    if echo "$line" | jq -e '.type == "turn.completed"' >/dev/null 2>&1; then
      echo "$(echo "$line" | jq -r '.message')"
    fi
  done

  if [ "$has_error" = true ]; then
    exit 1
  fi
}
```

**Source:** [Codex CLI Reference - JSON output](https://developers.openai.com/codex/cli/reference/); [JSON Lines format](https://jsonlines.org/); [jq manual](https://stedolan.github.io/jq/)

### Example 4: Idempotent File Writing (from /init-gsd)

```bash
# Check if file exists and should be skipped
if [ -f "AGENTS.md" ]; then
  if [ "$FORCE" = "true" ]; then
    echo "  Overwriting: AGENTS.md (--force flag)"
    # Proceed to write
  else
    echo "  Skipping: AGENTS.md (already exists)"
    exit 0
  fi
else
  echo "  Creating: AGENTS.md"
fi

# Write the file using Write tool
cat > AGENTS.md << 'EOF'
# [Project Name]

## Build & Test
[Auto-detected from package.json/pyproject.toml or user-filled placeholders]
EOF
```

**Source:** [Bash conditionals](https://www.gnu.org/software/bash/manual/html_node/Conditional-Constructs.html); Claude Code Write tool

### Example 5: Git Diff for Last N Commits (from /codex-review)

```bash
# Default to last 5 commits, allow override via --commits=N
COMMIT_COUNT=${COMMITS:-5}

# Get diff stat to show what changed
echo "Changes in last $COMMIT_COUNT commits:"
git diff HEAD~$COMMIT_COUNT --stat

# Get actual diff for detailed review
git diff HEAD~$COMMIT_COUNT
```

**Source:** [git-diff manual](https://git-scm.com/docs/git-diff)

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual code review after execution | Automated cross-review via Codex CLI | 2025 (Codex v2.0+) | Catches bugs earlier; scales to large codebases |
| Single-tool verification (GSD only) | Dual-tool verification (GSD + Codex) | 2026 Phase 1 | Different models catch different issues |
| Skills as custom code | Skills as prompt orchestration | Claude Code 2024+ | Faster iteration; no compilation; leverage model judgment |
| Global config templates (one-time install) | Dynamic detection + auto-creation | This phase | Reduces manual setup; works on existing projects |

**Deprecated/outdated:**
- **Manual git worktree setup:** Use automation scripts (not implemented in Phase 1, deferred to Phase 2)
- **Monolithic PLAN.md:** Smaller phase-specific PLAN files (already standard in GSD workflow)

## Open Questions

1. **Codex Timeout Configuration**
   - What we know: `codex.timeout_seconds` is configurable in `.planning/config.json`; default is 5 minutes
   - What's unclear: Should timeout be per-review or global? How to handle partial results?
   - Recommendation: Start with global timeout; if Codex times out mid-review, report "Incomplete" and let user decide

2. **JSONL Parsing Robustness**
   - What we know: Codex outputs JSONL when `--json` flag is used; jq can parse it
   - What's unclear: How to handle malformed lines, truncated JSON, or mid-stream API errors?
   - Recommendation: Use `jq -e` with error suppression (`2>/dev/null`); track whether we received a final "turn.completed" event; if not, report incomplete

3. **Stack Detection Depth**
   - What we know: Check package.json (Node), pyproject.toml (Python), Makefile (any)
   - What's unclear: How many other config files should we check? (go.mod, Cargo.toml, Gemfile, etc.)
   - Recommendation: Start with the big three; leave placeholders for user to fill in if not detected; don't try to auto-detect every ecosystem

4. **Global Config Scope**
   - What we know: `~/.claude/CLAUDE.md` and `~/.codex/config.toml` are global; checked once per user
   - What's unclear: If they're outdated/wrong, should `/init-gsd` update them or warn the user?
   - Recommendation: Update only if missing; if they exist, assume user has customized them and warn: "Existing ~/.claude/CLAUDE.md found. Skipping global config update. (Use --force to update.)"

## Validation Architecture

> Validation skipped: `workflow.nyquist_validation` not present in `.planning/config.json` (testing not required for Phase 1)

## Sources

### Primary (HIGH confidence)

- **Claude Code Skills Documentation** — [Extend Claude with Skills](https://code.claude.com/docs/en/skills)
  - Frontmatter reference (`disable-model-invocation`, `allowed-tools`)
  - Skill invocation control patterns
  - Supporting files and dynamic context

- **Codex CLI Official Reference** — [Command-line options](https://developers.openai.com/codex/cli/reference/)
  - `--full-auto`, `--json`, `--ephemeral` flags
  - JSONL event types (turn.completed, error, item.*)
  - Non-interactive execution model

- **GSD Framework** — `.planning/REQUIREMENTS.md`, `.planning/STATE.md`, existing SKILL.md files
  - Phase structure and requirement mapping
  - Current state and phase positioning
  - Detailed step-by-step instructions in SKILL.md

### Secondary (MEDIUM confidence)

- **JSON Lines Format** — [JSONL specification](https://jsonlines.org/)
  - Newline-delimited JSON format
  - Verified with multiple sources on JSONL parsing

- **Git Documentation** — [git-diff](https://git-scm.com/docs/git-diff), [git-worktree](https://git-scm.com/docs/git-worktree)
  - Standard git operations
  - Worktree patterns for parallel work

- **Bash Best Practices** — [GNU Bash Manual](https://www.gnu.org/software/bash/manual/)
  - Error handling, command substitution, conditionals
  - Subprocess management patterns

### Tertiary (LOW confidence — flagged for validation)

- **Codex Timeout Behavior** — Not explicitly documented; inferred from common async patterns
  - Recommendation: Test actual timeout behavior during implementation

- **JSONL Parsing Edge Cases** — WebSearch verified but not from official Codex docs
  - Recommendation: Test partial/truncated output during `/gsd-codex-verify` implementation

## Metadata

**Confidence breakdown:**
- **Standard Stack:** HIGH — Verified via Claude Code official docs, GSD framework, and Codex CLI reference
- **Architecture Patterns:** HIGH — All patterns documented in official sources or proven in existing SKILL.md files
- **Pitfalls:** MEDIUM — Based on careful analysis of spec and common failure modes; to be validated during implementation
- **Code Examples:** MEDIUM-HIGH — Verified from official docs; some bash patterns are de-facto standards

**Research date:** 2026-03-02
**Valid until:** 2026-03-16 (2 weeks — fast-moving area; Codex updates frequently)
