# Phase 03: Entropy Management - Research

**Researched:** 2026-03-11
**Domain:** Shell-based codebase analysis tools (doc consistency, architecture validation, TODO tracking, scheduling)
**Confidence:** HIGH

## Summary

Phase 03 adds four entropy detection tools that run as scheduled sweeps (not pre-commit gates). The core challenge is building lightweight shell scripts that detect drift between documentation conventions and actual code, reuse the existing architecture validator, track stale TODOs via `git blame`, and store schedule config in `.planning/config.json`.

All four requirements map cleanly to standalone shell scripts in `bin/` that follow the exact patterns established in Phase 02 (JSON stdout, human-readable stderr, exit codes). ENTR-02 is trivially solved by wrapping `validate-architecture.sh` with full-project file scanning. The other three require new but straightforward scripts.

**Primary recommendation:** Build `bin/entropy-sweep.sh` as the orchestrator (mirrors `bin/gate-check.sh` pattern) that dispatches to three check scripts: `check-doc-consistency.sh`, `check-stale-todos.sh`, and the existing `validate-architecture.sh`. Store schedule config in `config.json` under an `entropy` key. No new dependencies required -- only bash, git, and node (already available).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None -- all decisions deferred to Claude's judgment.

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
| ENTR-01 | Scheduled doc consistency check (do AGENTS.md conventions match actual code patterns?) | `bin/check-doc-consistency.sh` -- parse AGENTS.md conventions, grep codebase for violations |
| ENTR-02 | Constraint violation scanning between milestones (architecture rules still hold?) | Reuse `bin/validate-architecture.sh` with full project file list instead of staged-only |
| ENTR-03 | Stale TODO/FIXME detection with age tracking | `bin/check-stale-todos.sh` -- grep for TODO/FIXME, `git blame` for date, compute age in days |
| ENTR-04 | Configurable schedule via `.planning/config.json` (daily/weekly/on-push) | Add `entropy` section to config.json with `schedule` and per-check enable flags |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| bash | 5.x | Script runtime | All Phase 02 scripts are bash; consistency |
| git blame | 2.43+ | TODO age tracking | Built-in, no dependencies, line-level authorship with dates |
| node (inline) | 18+ | JSON processing | Already used by gate-check.sh for reliable JSON handling |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| grep -rn | GNU | Pattern scanning | Doc convention checks, TODO/FIXME detection |
| date | GNU | Age calculation | Computing days since TODO introduction |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| git blame for age | git log -S | blame gives per-line dates; log -S gives first-commit but harder to parse |
| grep for conventions | AST parser | Phase 02 decision: regex-based, not AST -- same applies here |
| bash orchestrator | Node CLI | Phase 02 decision: shell-based to match bin/ conventions |

**Installation:**
```bash
# No new dependencies -- all tools already available
```

## Architecture Patterns

### Recommended Project Structure
```
bin/
  entropy-sweep.sh          # Orchestrator (like gate-check.sh)
  check-doc-consistency.sh  # ENTR-01: AGENTS.md vs code
  check-stale-todos.sh      # ENTR-03: TODO/FIXME with age
  validate-architecture.sh  # ENTR-02: already exists (reuse)
  test-entropy-sweep.sh     # Tests for sweep orchestrator
  test-check-doc-consistency.sh  # Tests for doc checker
  test-check-stale-todos.sh     # Tests for TODO checker
```

### Pattern 1: Sweep Orchestrator (mirrors gate-check.sh)
**What:** `entropy-sweep.sh` reads config, dispatches to individual check scripts, aggregates JSON results
**When to use:** Always -- this is the single entry point for all entropy checks
**Example:**
```bash
# Output format (JSON to stdout, human summary to stderr)
{
  "sweep_type": "manual",
  "timestamp": "2026-03-11T10:00:00Z",
  "checks": [
    {"name": "doc-consistency", "passed": true, "findings": []},
    {"name": "architecture", "passed": true, "findings": []},
    {"name": "stale-todos", "passed": false, "findings": [
      {"file": "bin/demo.sh", "line": 42, "text": "TODO: cleanup", "age_days": 45, "author": "dev"}
    ]}
  ],
  "summary": {"total_findings": 1, "critical": 0}
}
```

### Pattern 2: Doc Consistency Check (ENTR-01)
**What:** Parse AGENTS.md conventions section, generate grep patterns, scan codebase
**When to use:** To detect drift between documented conventions and actual code
**Approach:**
The AGENTS.md conventions are:
1. "Write tests for all new features"
2. "No debug/log statements in production code"
3. "Keep functions small and focused"
4. "Each commit should be atomic and revertable"
5. "Skills must work across Claude Code sessions without re-explaining"
6. "All instruction files must stay under 200 lines for >92% rule adherence"

Checkable conventions (automated):
- **No debug/log statements**: grep for `console.log`, `console.debug`, `echo "DEBUG"` in production files (exclude test files)
- **Instruction files under 200 lines**: `wc -l` on all `SKILL.md`, `AGENTS.md`, skill rule files
- **Tests exist for features**: check that `bin/*.sh` (non-test) has a corresponding `test-*.sh`

Non-checkable conventions (skip with note):
- "Keep functions small" -- requires AST analysis, out of scope
- "Atomic commits" -- git history analysis, not file-level check
- "Skills work across sessions" -- behavioral, not static analysis

### Pattern 3: Stale TODO Detection (ENTR-03)
**What:** Find TODO/FIXME comments, use `git blame` for introduction date, compute age
**When to use:** To surface forgotten cleanup items
**Key implementation detail:**
```bash
# For each TODO/FIXME match:
# 1. grep -rn "TODO\|FIXME" --include="*.sh" --include="*.js" ...
# 2. For each match, git blame -p <file> -L <line>,<line>
# 3. Parse author-time from blame porcelain output
# 4. Compute: age_days = (now - author_time) / 86400
```

**git blame porcelain format** (verified, HIGH confidence):
```
<sha> <orig-line> <final-line> <num-lines>
author <name>
author-mail <email>
author-time <unix-timestamp>    <-- this is what we need
author-tz <offset>
...
```

### Pattern 4: Architecture Sweep (ENTR-02)
**What:** Run existing `validate-architecture.sh` against ALL project files, not just staged
**When to use:** Between milestones to catch accumulated violations
**Implementation:** Simply collect all source files and pass to existing validator:
```bash
# Collect all non-.planning, non-node_modules, non-.git files
find . -type f \( -name "*.sh" -o -name "*.js" -o -name "*.cjs" -o -name "*.ts" \) \
  -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./.planning/*" \
  | sed 's|^\./||' \
  | xargs bin/validate-architecture.sh .architecture.json
```

### Pattern 5: Config Schema (ENTR-04)
**What:** Add `entropy` section to `.planning/config.json`
**Schema:**
```json
{
  "entropy": {
    "enabled": true,
    "schedule": "weekly",
    "checks": {
      "doc_consistency": { "enabled": true },
      "architecture": { "enabled": true },
      "stale_todos": {
        "enabled": true,
        "warn_after_days": 30,
        "critical_after_days": 90
      }
    }
  }
}
```
Schedule values: `"daily"`, `"weekly"`, `"on-push"`, `"manual"`. The schedule field is informational metadata (consumed by the user or future CI integration). The scripts themselves run on-demand; the schedule tells the user *when* they should run them.

### Anti-Patterns to Avoid
- **Building a daemon/scheduler**: The schedule config is metadata, not runtime -- scripts run when invoked, schedule tells you *when* to invoke
- **Modifying validate-architecture.sh**: Reuse it as-is; the sweep orchestrator handles full-project file collection
- **Over-parsing AGENTS.md**: Don't try to understand every convention semantically -- match what's grep-able, skip what isn't
- **Blocking on TODOs**: Entropy sweep reports findings but does NOT block anything (unlike gates which block commits)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Architecture validation | New validator | Existing `validate-architecture.sh` | Already tested, handles all edge cases |
| JSON aggregation | String concatenation | `node -e` inline | Reliable escaping, same pattern as gate-check.sh |
| Date arithmetic | bash arithmetic | `node -e` or `date -d` | Cross-platform date parsing is error-prone in pure bash |
| Git blame parsing | Custom parser | `git blame -p` (porcelain) | Stable machine-readable format, one line per field |

**Key insight:** Phase 02 already solved the hardest problems (JSON output format, config reading, test fixture patterns). Phase 03 reuses all of these.

## Common Pitfalls

### Pitfall 1: git blame on uncommitted files
**What goes wrong:** `git blame` fails on files not tracked by git
**Why it happens:** New files with TODOs won't have blame data
**How to avoid:** Check `git ls-files <file>` first; for untracked files, use current date as introduction date
**Warning signs:** Script crashes on new test projects or newly added files

### Pitfall 2: Overly strict doc consistency checking
**What goes wrong:** False positives from convention checks (e.g., flagging test files for containing `console.log`)
**Why it happens:** Conventions like "no debug statements" apply to production code, not test code
**How to avoid:** Exclude test files (`test-*.sh`, `*.test.js`) from production-code conventions
**Warning signs:** Every run produces dozens of noise findings

### Pitfall 3: Date computation across timezones
**What goes wrong:** Age calculation off by a day depending on timezone
**Why it happens:** `git blame` author-time is UTC epoch, but local `date` may use local timezone
**How to avoid:** Use UTC throughout: `date -u +%s` for current time, blame author-time is already epoch
**Warning signs:** TODO ages fluctuate by +/-1 day between runs

### Pitfall 4: Config schema migration
**What goes wrong:** Existing `config.json` files break when new `entropy` section is expected
**Why it happens:** Phase 03 adds a new top-level key that older configs don't have
**How to avoid:** Default to enabled with sensible defaults when `entropy` key is absent (same pattern as gates config)
**Warning signs:** Script fails on projects that haven't updated config.json

### Pitfall 5: Performance on large codebases
**What goes wrong:** `git blame` on every TODO across hundreds of files is slow
**Why it happens:** Each `git blame -L` is a separate git process
**How to avoid:** First collect all TODOs with grep (fast), then batch blame calls. For very large repos, consider `git blame --porcelain` on whole files rather than line-by-line
**Warning signs:** Sweep takes >30 seconds on normal-sized projects

## Code Examples

### Reading config with defaults (from gate-check.sh pattern)
```bash
# Source: bin/gate-check.sh (Phase 02)
if [ -f "$CONFIG_FILE" ]; then
  ENTROPY_JSON=$(node -e "
    const c = JSON.parse(require('fs').readFileSync('$CONFIG_FILE','utf8'));
    const e = c.entropy || {};
    console.log(JSON.stringify({
      enabled: e.enabled !== undefined ? e.enabled : true,
      schedule: e.schedule || 'weekly',
      doc_consistency: e.checks ? (e.checks.doc_consistency ? e.checks.doc_consistency.enabled !== false : true) : true,
      architecture: e.checks ? (e.checks.architecture ? e.checks.architecture.enabled !== false : true) : true,
      stale_todos: e.checks ? (e.checks.stale_todos ? e.checks.stale_todos.enabled !== false : true) : true,
      warn_days: e.checks && e.checks.stale_todos ? (e.checks.stale_todos.warn_after_days || 30) : 30,
      critical_days: e.checks && e.checks.stale_todos ? (e.checks.stale_todos.critical_after_days || 90) : 90
    }));
  " 2>/dev/null || echo '{}')
fi
```

### git blame porcelain for date extraction
```bash
# Get introduction date for a specific line
get_blame_date() {
  local file="$1" line="$2"
  # Check if file is tracked
  if ! git ls-files --error-unmatch "$file" >/dev/null 2>&1; then
    date -u +%s  # untracked: use current time
    return
  fi
  git blame -p "$file" -L "$line,$line" 2>/dev/null \
    | grep '^author-time ' \
    | cut -d' ' -f2
}
```

### Test fixture pattern (from Phase 02)
```bash
# Source: bin/test-gate-check.sh (Phase 02)
make_fixture() {
  local name="$1"
  FIXTURE_DIR="$TMPDIR_ROOT/$name"
  mkdir -p "$FIXTURE_DIR/bin" "$FIXTURE_DIR/.planning"
  cd "$FIXTURE_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  # ... setup config, files, etc.
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Ad-hoc manual review | Automated sweep scripts | Phase 03 | Entropy caught systematically |
| Gate-only validation (staged files) | Full-project sweeps | Phase 03 | Catches accumulated drift, not just per-commit |
| No TODO tracking | Age-aware TODO detection | Phase 03 | Prevents forgotten cleanup items |

## Open Questions

1. **Should sweep results be stored persistently?**
   - What we know: Gate results are ephemeral (stdout per run). Sweep results could be saved to track trends.
   - What's unclear: Whether trend tracking adds value at this stage
   - Recommendation: Start ephemeral (like gates), defer persistence to a future phase

2. **Should entropy-sweep.sh be invokable as a skill?**
   - What we know: Gate-check has a `skills/gate-check/` skill wrapper
   - What's unclear: Whether a skill wrapper adds value for sweeps (they're run less frequently)
   - Recommendation: Build the scripts first, add a skill wrapper only if the orchestrator needs to invoke sweeps programmatically

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash test scripts (project convention) |
| Config file | none -- tests are standalone bash scripts |
| Quick run command | `bash bin/test-entropy-sweep.sh` |
| Full suite command | `bash bin/test-entropy-sweep.sh && bash bin/test-check-doc-consistency.sh && bash bin/test-check-stale-todos.sh` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ENTR-01 | Doc consistency detects debug statements in prod code | unit | `bash bin/test-check-doc-consistency.sh` | No -- Wave 0 |
| ENTR-01 | Doc consistency skips test files | unit | `bash bin/test-check-doc-consistency.sh` | No -- Wave 0 |
| ENTR-01 | Doc consistency checks instruction file line counts | unit | `bash bin/test-check-doc-consistency.sh` | No -- Wave 0 |
| ENTR-02 | Architecture sweep scans all project files | unit | `bash bin/test-entropy-sweep.sh` | No -- Wave 0 |
| ENTR-03 | Stale TODO detection finds TODO/FIXME comments | unit | `bash bin/test-check-stale-todos.sh` | No -- Wave 0 |
| ENTR-03 | Age tracking uses git blame dates | unit | `bash bin/test-check-stale-todos.sh` | No -- Wave 0 |
| ENTR-03 | Warn/critical thresholds from config | unit | `bash bin/test-check-stale-todos.sh` | No -- Wave 0 |
| ENTR-04 | Config defaults when entropy section absent | unit | `bash bin/test-entropy-sweep.sh` | No -- Wave 0 |
| ENTR-04 | Schedule value stored in config | unit | `bash bin/test-entropy-sweep.sh` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `bash bin/test-entropy-sweep.sh` (quick, <10s)
- **Per wave merge:** Full suite (all three test scripts)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `bin/test-entropy-sweep.sh` -- covers ENTR-02, ENTR-04
- [ ] `bin/test-check-doc-consistency.sh` -- covers ENTR-01
- [ ] `bin/test-check-stale-todos.sh` -- covers ENTR-03
- [ ] Test fixtures need git repos (same pattern as Phase 02 test-gate-check.sh)

## Sources

### Primary (HIGH confidence)
- `bin/gate-check.sh` -- Phase 02 orchestrator pattern (JSON stdout, stderr human output, config reading)
- `bin/validate-architecture.sh` -- Existing architecture validator to reuse for ENTR-02
- `bin/test-gate-check.sh` -- Test fixture patterns (temp git repos, pass/fail helpers)
- `.planning/config.json` -- Existing config schema to extend
- `.architecture.json` -- Existing architecture rules
- `AGENTS.md` -- Source of conventions to check for ENTR-01
- `git blame -p` man page -- porcelain format for date extraction

### Secondary (MEDIUM confidence)
- git blame performance characteristics -- based on project experience, not benchmarked

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- reuses existing Phase 02 patterns exactly
- Architecture: HIGH -- direct extension of established gate-check.sh pattern
- Pitfalls: HIGH -- based on concrete Phase 02 experience and git blame known behavior

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable domain, no external dependencies)
