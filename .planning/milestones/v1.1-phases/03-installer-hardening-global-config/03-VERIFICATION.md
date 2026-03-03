---
phase: 03-installer-hardening-global-config
verified: 2026-03-02T09:00:00Z
status: human_needed
score: 10/10 must-haves verified
re_verification: true
previous_status: gaps_found
previous_score: 8/10
gaps_closed:
  - "ROADMAP SC1 now says 'git or node' (not 'Claude Code or git') — verified at ROADMAP.md line 38"
  - "ROADMAP SC4 now says 'conservative approval defaults' (not '--full-auto defaults') — verified at ROADMAP.md line 41"
  - "INST-01 now lists claude/codex as optional, git/node as required — verified at REQUIREMENTS.md line 29"
  - "CONF-02 now describes conservative approval defaults (untrusted policy) — verified at REQUIREMENTS.md line 36"
gaps_remaining: []
regressions: []
human_verification:
  - test: "Run bash install.sh on a machine with git/node but without claude CLI installed"
    expected: "Warning message appears naming claude as missing with install URL, script continues and completes successfully"
    why_human: "Cannot simulate missing claude binary in this environment"
  - test: "Run bash install.sh followed by bash install.sh again (no --force)"
    expected: "Second run shows skipped messages for all config files with clear 'exists, skipping' text, does not overwrite"
    why_human: "Requires live filesystem state to observe skip behavior"
  - test: "Run bash install.sh --force on a machine with existing configs"
    expected: "All config files overwritten, output shows 'Installed (force):' for each"
    why_human: "Requires live filesystem with existing configs"
---

# Phase 3: Installer Hardening & Global Config Verification Report

**Phase Goal:** Users get reliable installation with clear feedback and sensible defaults for both tools
**Verified:** 2026-03-02T09:00:00Z
**Status:** human_needed
**Re-verification:** Yes — after gap closure (plan 03-03)

## Re-verification Summary

Both gaps from the initial verification (score 8/10) are now closed:

- **Gap 1 resolved:** ROADMAP SC1 (line 38) now reads "missing git or node" — no longer references "Claude Code or git". REQUIREMENTS.md INST-01 (line 29) now explicitly lists claude/codex as optional dependencies and git/node as required.
- **Gap 2 resolved:** ROADMAP SC4 (line 41) now reads "conservative approval defaults". REQUIREMENTS.md CONF-02 (line 36) now reads "conservative approval defaults (untrusted policy)" — no longer references "--full-auto defaults".

The SUMMARY for plan 03-03 notes that ROADMAP.md was already correct (updated during plan creation) and only REQUIREMENTS.md required actual edits (commit `a034ff8`). Both documents were verified directly against the file contents — not the SUMMARY claims.

No regressions detected in install.sh or test-install.sh; no code files were modified by plan 03-03.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Running install.sh on a machine missing git or node produces a clear error naming the missing dep with install hint | VERIFIED | `preflight_check()` at line 58: git/node checked via `command -v`, missing_required array with platform-specific hints (brew/apt/URL), exit 1 if non-empty |
| 2 | Running install.sh on a machine missing claude or codex prints a warning and continues | VERIFIED | Lines 95-104: `if ! command -v claude` calls `warn()`, `if ! command -v codex` calls `warn()`, no exit |
| 3 | Running install.sh with --force overwrites all config files with fresh templates | VERIFIED | Lines 47-48: FORCE flag parsed. Lines 159, 182, 257, 273: all config sections check `[ "$FORCE" = true ]` and overwrite |
| 4 | Running install.sh without --force skips existing config files with a message | VERIFIED | All config sections check `elif [ -f "$dest" ]` and call `ok "... exists, skipping"` + increment SKIPPED. SKIPPED_FILES array tracks skipped paths |
| 5 | After install completes, a summary shows counts of installed, skipped, warnings, and errors | VERIFIED | Line 461: `echo -e " Status: ${BOLD}$INSTALLED installed${RESET}, $SKIPPED skipped, ${YELLOW}$WARNINGS warnings${RESET}, ${RED}$ERRORS errors${RESET}"` |
| 6 | After install completes, an integrity check compares each installed file against its source | VERIFIED | `verify_integrity()` at line 333, called at line 427. Uses `cmp -s` for skills (strict), rules and codex configs (skipped-aware). SKIPPED_FILES array exempts user-skipped files |
| 7 | ANSI colors used for output with TTY fallback | VERIFIED | Lines 22-34: `if [ -t 1 ]`, RED/GREEN/YELLOW/BOLD/RESET set or empty. `ok()`/`warn()`/`err()` helpers use colors |
| 8 | ROADMAP SC1 says "git or node" as hard-error deps — specs match implementation | VERIFIED | ROADMAP.md line 38: "missing git or node". REQUIREMENTS.md line 29: "required dependencies (git, node) and optional dependencies (claude, codex)" |
| 9 | test-install.sh reports diff-based integrity results alongside existence checks | VERIFIED | `check_integrity()` at line 22: uses `cmp -s`, strict mode = FAIL on mismatch, template mode = WARN. Sections for skills (strict), rules (template), configs (template) |
| 10 | ROADMAP SC4 / CONF-02 describe conservative defaults — specs match implementation | VERIFIED | ROADMAP.md line 41: "conservative approval defaults". REQUIREMENTS.md line 36: "conservative approval defaults (untrusted policy)" |

**Score:** 10/10 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `install.sh` | Hardened installer with pre-flight checks, integrity validation, ANSI output, --force flag | VERIFIED | 468 lines. Functions: `preflight_check()` (line 58), `verify_integrity()` (line 333). FORCE flag (line 47). ANSI TTY detection (lines 22-34). All config sections use skip-if-exists with SKIPPED_FILES tracking |
| `test-install.sh` | Diff-based integrity validation for installed files | VERIFIED | 103 lines. `check_integrity()` function (line 22) with strict/template modes. Sections: skill integrity (line 73), rules integrity (line 85), config integrity (line 93). WARN counter (line 10). Summary shows pass/fail/warn (line 99) |
| `.planning/ROADMAP.md` | Updated SC1 ("git or node") and SC4 ("conservative approval defaults") | VERIFIED | Line 38: "missing git or node". Line 41: "conservative approval defaults". Line 47: 03-03 plan entry present. Plans count: 3 |
| `.planning/REQUIREMENTS.md` | Updated INST-01 (optional deps) and CONF-02 (conservative defaults) — all 6 IDs remain [x] | VERIFIED | Line 29: INST-01 lists git/node as required, claude/codex as optional. Line 36: CONF-02 describes conservative approval defaults (untrusted policy). All 6 IDs (INST-01 through CONF-03) marked [x] |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| install.sh | global/codex-agents.md | cp for config template | WIRED | Lines 258, 266: `cp "$SCRIPT_DIR/global/codex-agents.md" "$CODEX_AGENTS"` |
| install.sh | global/codex-config.toml | cp for config template | WIRED | Lines 274, 282: `cp "$SCRIPT_DIR/global/codex-config.toml" "$CODEX_CONFIG"` |
| install.sh | skills/ | cp -r for skill installation | WIRED | Lines 136, 140: `cp -r "$skill_dir"* "$dest/"` |
| test-install.sh | install.sh | Validates same file pairs | WIRED | Lines 74-95: skill_dir loop (strict cmp), rules loop (template cmp), codex-agents.md and codex-config.toml (template cmp) mirror install.sh targets |
| ROADMAP.md | install.sh | SC1/SC4 describe actual behavior | WIRED | SC1 line 38 matches install.sh preflight (git/node hard fail, claude optional). SC4 line 41 matches codex-config.toml (untrusted policy) |
| REQUIREMENTS.md | install.sh | INST-01/CONF-02 describe actual behavior | WIRED | INST-01 line 29 matches preflight_check() behavior. CONF-02 line 36 matches codex-config.toml default profile |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| INST-01 | 03-01-PLAN.md, 03-03-PLAN.md | install.sh checks required deps (git, node) and optional deps (claude, codex) before installing | SATISFIED | `preflight_check()` lines 70-115: git/node → missing_required array + exit 1; claude/codex → warn() + continue. REQUIREMENTS.md line 29 matches |
| INST-02 | 03-01-PLAN.md, 03-02-PLAN.md | install.sh validates installed file integrity after copy | SATISFIED | `verify_integrity()` (install.sh line 333) uses cmp -s on all installed files. `check_integrity()` (test-install.sh line 22) provides standalone validation |
| INST-03 | 03-01-PLAN.md | Clear error messages with resolution steps for missing deps | SATISFIED | `preflight_check()` provides platform-specific install hints (brew/apt for git/node, URLs for claude/codex) |
| CONF-01 | 03-01-PLAN.md | Global Claude config template to ~/.claude/ with dual-tool defaults | SATISFIED | Section 3 (lines 179-244): heredoc template with dual-tool workflow content, skip-if-exists, --force support |
| CONF-02 | 03-01-PLAN.md, 03-03-PLAN.md | Global Codex config with conservative approval defaults | SATISFIED | global/codex-config.toml ships with approval_policy = "untrusted" as default. REQUIREMENTS.md CONF-02 now correctly describes this as "conservative approval defaults (untrusted policy)" |
| CONF-03 | 03-01-PLAN.md | Config templates non-destructive (skip if user config exists) | SATISFIED | All config sections (rules, CLAUDE.md, AGENTS.md, config.toml) check file existence and skip with message if present without --force |

All 6 requirement IDs declared in plan frontmatter are covered. No orphaned requirements found — REQUIREMENTS.md traceability table maps INST-01 through CONF-03 exclusively to Phase 3.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | — | — | — | No TODO/FIXME/placeholder/empty implementations detected in install.sh, test-install.sh, ROADMAP.md, or REQUIREMENTS.md |

### Human Verification Required

#### 1. Optional dependency warning flow

**Test:** On a machine without claude CLI installed, run `bash install.sh`
**Expected:** Yellow warning message: "claude not found. Install: https://docs.anthropic.com/en/docs/claude-code" — script continues and completes without exiting
**Why human:** Cannot simulate a missing binary in this environment

#### 2. Skip-if-exists behavior

**Test:** Run `bash install.sh` on a freshly set-up machine, then run it again immediately
**Expected:** Second run shows "exists, skipping" for all config files (CLAUDE.md, rules, AGENTS.md, config.toml). Summary shows SKIPPED count > 0 and INSTALLED count equals only skills (which always update)
**Why human:** Requires live installation state to verify skip messages

#### 3. --force overwrite behavior

**Test:** Run `bash install.sh`, then modify `~/.codex/AGENTS.md`, then run `bash install.sh --force`
**Expected:** "Installed (force): ~/.codex/AGENTS.md" appears, file reverts to template content
**Why human:** Requires live filesystem manipulation to verify

### Re-verification: Gap Closure Confirmation

| Gap | Previous Status | Current Status | How Closed |
|-----|-----------------|----------------|------------|
| ROADMAP SC1 says "Claude Code or git" but code treats claude as optional | FAILED | VERIFIED | ROADMAP.md line 38 updated to "missing git or node". REQUIREMENTS.md line 29 updated to list claude/codex as optional. Plan 03-03, commit a034ff8 |
| CONF-02 says "--full-auto defaults" but code uses untrusted/conservative defaults | FAILED | VERIFIED | ROADMAP.md line 41 updated to "conservative approval defaults". REQUIREMENTS.md line 36 updated to "conservative approval defaults (untrusted policy)". Plan 03-03, commit a034ff8 |

No regressions: install.sh (468 lines) and test-install.sh (103 lines) are byte-for-byte identical to initial verification — plan 03-03 was spec-only, no code was modified.

---

_Verified: 2026-03-02T09:00:00Z_
_Verifier: Claude (gsd-verifier)_
_Re-verification after: plan 03-03 (spec alignment gap closure)_
