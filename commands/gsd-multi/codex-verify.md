---
name: gsd-multi:codex-verify
description: Full dual-tool verification gate -- runs GSD verify-work first, then cross-model review where each tool checks the other's output. This is the combined quality gate before advancing phases.
argument-hint: [focus-area]
allowed-tools: Read, Write, Bash, Glob, Grep
---

# Full Dual-Tool Verification Gate (/gsd-multi:codex-verify)

This skill is the combined quality gate before advancing phases. It runs GSD structural verification first, then cross-model review where each tool reviews the OTHER's work.

Execute the following 9 steps IN ORDER. Do not skip steps. Handle all error conditions as specified.

---

## Step 1: Parse Arguments and Gather Context

### 1a. Extract focus area

If `$ARGUMENTS` is provided, use it as the focus area for cross-review. Otherwise default to `"general quality review"`.

```bash
FOCUS_AREA="$ARGUMENTS"
if [ -z "$FOCUS_AREA" ]; then
  FOCUS_AREA="general quality review"
fi
```

Store `FOCUS_AREA` for later steps.

### 1b. Read planning state

Use the Read tool for each of these files. If a file does not exist, note it and continue.

- `.planning/STATE.md` -- identify current phase, plan position, status
- `.planning/config.json` -- extract `codex.timeout_seconds` (default: 300 if key missing or file missing)

Store `TIMEOUT_SECONDS` and `CURRENT_PHASE` (e.g., `01-core-skill-implementation`).

### 1c. Determine phase directory

From STATE.md, derive the phase directory path:

```
PHASE_DIR=".planning/phases/${CURRENT_PHASE}/"
```

Verify it exists with Bash. If missing, print `ERROR: Phase directory not found at ${PHASE_DIR}. Cannot proceed.` and STOP.

---

## Step 2: Run GSD Structural Verification

Print:
```
Step 1/3: Running GSD structural verification...
```

Invoke `/gsd:verify-work` to run the GSD verifier agent. This checks all plan artifacts against specs, REQUIREMENTS.md, and ROADMAP.md.

Wait for the verification to complete.

---

## Step 3: Gate on GSD Results

After `/gsd:verify-work` completes, read the generated verification file from the phase directory:

```bash
ls ${PHASE_DIR}/*-VERIFICATION.md 2>/dev/null
```

Use the Read tool to read the most recent VERIFICATION.md file found.

### 3a. Parse the result

Look for overall PASS or FAIL status in the verification output.

### 3b. Apply the gate

**If GSD verification FAILED:**
- Print the failure details (which checks failed, what gaps exist)
- Print: `"GSD verification failed. Fix structural issues before cross-review."`
- Print: `"Run /gsd:execute-phase to address gaps, then re-run /gsd-multi:codex-verify."`
- Write a partial VERIFICATION.md to the phase directory (GSD results only, cross-review skipped):

  ```
  # Dual-Tool Verification Report

  **Timestamp:** {ISO timestamp}
  **Phase:** {phase name}
  **Status:** FAIL (GSD verification failed -- cross-review skipped)

  ## GSD Structural Verification: FAIL
  {failure details}

  ## Cross-Model Review: SKIPPED
  GSD verification must pass before cross-review runs.
  ```

- **STOP HERE** -- do not proceed to cross-review.

**If GSD verification PASSED:** Continue to Step 4.

**If VERIFICATION.md not found or /gsd:verify-work failed to run:**
- Print: `"WARNING: GSD verification could not be completed. Verification file not found."`
- Print: `"Proceeding with cross-review, but GSD structural compliance is unconfirmed."`
- Set `GSD_STATUS="UNKNOWN"` and continue.

---

## Step 4: Check Codex Availability

Run via Bash:

```bash
command -v codex >/dev/null 2>&1 && echo "INSTALLED" || echo "NOT_INSTALLED"
```

- **If NOT installed:**
  - Print: `"WARNING: Codex CLI not installed. Skipping cross-model review layer."`
  - Print: `"Install with: npm install -g @openai/codex"`
  - Print: `"GSD verification passed. Cross-review skipped (Codex not available)."`
  - Set `CODEX_AVAILABLE=false`
  - Skip to Step 7 (build report with GSD results only)

- **If installed:**
  - Set `CODEX_AVAILABLE=true`
  - Print: `"Codex CLI detected. Cross-model review enabled."`

---

## Step 5: Identify Who Built What

Print:
```
Step 2/3: Running cross-model review...
```

### 5a. Get phase commits

Check git log for commits related to the current phase:

```bash
git log --oneline --all --since="7 days ago" 2>/dev/null | head -30
```

### 5b. Identify Codex-authored commits

Look for commits authored by or mentioning Codex:

```bash
git log --oneline --all --author="codex" --since="7 days ago" 2>/dev/null || true
git log --oneline --all --grep="codex" --grep="Codex" --grep="\[codex\]" --since="7 days ago" 2>/dev/null || true
```

Store matching commits. If none found, set `CODEX_COMMITS_FOUND=false`.

### 5c. Identify Claude-authored commits

Everything else in the phase is considered Claude-authored. Store those commit hashes.

---

## Step 6: Run Cross-Model Reviews

### 6a: Claude Reviews Codex's Autonomous Output

**If `CODEX_COMMITS_FOUND=false`:**
- Record: `"N/A - no Codex-built changes found"`
- Set `CLAUDE_REVIEW_STATUS="N/A"`
- Skip to 6b.

**If Codex-built changes exist:**
- For each Codex-authored commit, run `git show {hash}` to read those changes
- Read the relevant PLAN.md and REQUIREMENTS.md for the current phase
- Review the Codex changes for:
  1. **Spec compliance** -- Does the code meet requirements?
  2. **Incomplete implementations** -- TODO/FIXME/placeholder patterns?
  3. **Missing edge cases** -- Error handling, null checks, boundary conditions?
  4. **Test gaps** -- Are there tests for new functionality?
  5. **Architectural mismatches** -- Does the code follow patterns in AGENTS.md?
  6. **Security issues** -- Input validation, injection risks, auth checks?
- Record findings with severity levels:
  - `CRITICAL:` -- must fix before shipping
  - `WARNING:` -- should fix, not blocking
  - `INFO:` -- suggestion for improvement
- Set `CLAUDE_REVIEW_STATUS`:
  - `"PASS"` if no CRITICAL or WARNING findings
  - `"FAIL"` if any CRITICAL findings
  - `"WARNING"` if WARNING but no CRITICAL findings

### 6b: Codex Reviews Claude's Complex Work (via JSONL)

**Only execute if `CODEX_AVAILABLE=true`.** Otherwise set `CODEX_REVIEW_STATUS="SKIPPED"` and skip to Step 7.

#### Construct the review prompt

Build a review prompt that includes:
1. Project requirements summary (key points from REQUIREMENTS.md)
2. Current phase context (phase name, position from STATE.md)
3. Focus area from Step 1
4. A summary of Claude-authored changes (commit messages and file list)
5. The review checklist:
   - Bugs and logic errors
   - Security vulnerabilities
   - Missing test coverage
   - Edge cases and error handling gaps
   - Convention violations per AGENTS.md
   - Over-engineering or unnecessary complexity
6. Required output format: `CRITICAL:`, `WARNING:`, `INFO:`, or `PASS`

#### Execute with JSONL output

Run via Bash:

```bash
timeout ${TIMEOUT_SECONDS} codex exec --full-auto --json "${REVIEW_PROMPT}" 2>/tmp/codex-verify-stderr.txt | tee /tmp/codex-verify-output.jsonl
CODEX_EXIT=$?
```

#### Parse the JSONL output

Read `/tmp/codex-verify-output.jsonl` with the Read tool. Parse line-by-line:

- Initialize: `has_error=false`, `has_completed=false`, `review_output=""`
- For each line:
  - Attempt to parse as JSON
  - **If parse fails** (malformed line): log `"Skipping malformed JSONL line"` and continue. Do NOT crash.
  - If `.type == "error"`: set `has_error=true`, extract `.message` as error details
  - If `.type == "turn.completed"`: set `has_completed=true`, extract `.message` as the review output
  - Ignore other event types (`turn.started`, `item.file_write`, etc.)

#### Determine Codex review result

- **If `has_error=true`:** Set `CODEX_REVIEW_STATUS="FAIL"` with error message
- **If `has_completed=true` and no error:** Parse the review message for CRITICAL/WARNING/INFO findings. Set status accordingly:
  - Any CRITICAL: `CODEX_REVIEW_STATUS="FAIL"`
  - WARNING but no CRITICAL: `CODEX_REVIEW_STATUS="WARNING"`
  - No issues or PASS: `CODEX_REVIEW_STATUS="PASS"`
- **If neither completed nor error** (truncated/empty output): Set `CODEX_REVIEW_STATUS="INCOMPLETE"`, note partial output

#### Handle timeout

Check exit code from the `timeout` command:
- **Exit 124 (timeout):** Print `"Codex review timed out after ${TIMEOUT_SECONDS}s. Results may be incomplete."`. Read any partial output from `/tmp/codex-verify-output.jsonl`. Set `CODEX_REVIEW_STATUS="INCOMPLETE"`.
- **Other non-zero exit:** Print `"Codex review failed (exit ${CODEX_EXIT}). Continuing without Codex review."`. Read stderr from `/tmp/codex-verify-stderr.txt`. Set `CODEX_REVIEW_STATUS="INCOMPLETE"`.

---

## Step 7: Build Combined Report

Print:
```
Step 3/3: Building combined report...
```

### 7a. Determine overall status

Apply these rules in order:
- Any CRITICAL finding from any review layer: **overall = FAIL**
- Any WARNING but no CRITICAL: **overall = PASS (with warnings)**
- All PASS or N/A: **overall = PASS**
- Codex INCOMPLETE: **overall = PASS (with caveat)** -- note cross-review was incomplete
- GSD UNKNOWN: **overall = PASS (with caveat)** -- note GSD status unconfirmed

### 7b. Format the report

Use this exact format:

```
=== DUAL-TOOL VERIFICATION RESULTS ===

Phase: {phase name}
Focus: {FOCUS_AREA}
Timestamp: {ISO timestamp}

GSD Verifier (specs check):     {PASS|FAIL|UNKNOWN}
  {summary of GSD findings or "All structural checks passed"}

Claude reviewed Codex's work:   {PASS|FAIL|WARNING|N/A}
  {summary of Claude's findings on Codex output, or "No Codex-built changes found"}

Codex reviewed Claude's work:   {PASS|FAIL|WARNING|INCOMPLETE|SKIPPED}
  {summary of Codex's findings on Claude output, or reason for skip/incomplete}

Overall:                        {PASS|FAIL}
  {recommendation from Step 9 logic}

========================================
```

Display this report inline so the user sees it immediately.

---

## Step 8: Write VERIFICATION.md

Write the full report to `{PHASE_DIR}/{phase_number}-VERIFICATION.md` using the Write tool.

The file should contain:

```markdown
# Dual-Tool Verification Report

**Timestamp:** {ISO timestamp}
**Phase:** {phase name}
**Focus Area:** {FOCUS_AREA}
**Overall Status:** {PASS|FAIL}

## GSD Structural Verification: {PASS|FAIL|UNKNOWN}

{Detailed GSD findings -- paste relevant sections from the GSD verifier output}

## Claude Reviewed Codex's Work: {PASS|FAIL|WARNING|N/A}

{Detailed Claude findings on Codex output, or "No Codex-built changes in this phase."}

{If findings exist, list each with severity:}
- CRITICAL: {description}
- WARNING: {description}
- INFO: {description}

## Codex Reviewed Claude's Work: {PASS|FAIL|WARNING|INCOMPLETE|SKIPPED}

{Detailed Codex findings on Claude output}

{If findings exist, list each with severity:}
- CRITICAL: {description}
- WARNING: {description}
- INFO: {description}

{If SKIPPED: "Codex CLI not installed. Cross-model review layer unavailable."}
{If INCOMPLETE: "Codex review did not complete. Partial output below (if any)."}

## Overall Assessment

**Status:** {PASS|FAIL}
**Recommendation:** {recommendation text from Step 9}

## Appendix: Raw Codex Output

{If Codex ran, include relevant portions of the raw JSONL output or parsed review text.}
{If Codex did not run, note: "N/A - Codex review was skipped."}
```

After writing, print: `"Full report: {path to VERIFICATION.md}"`

---

## Step 9: Recommend Next Action

Based on overall status, print the appropriate recommendation:

- **All PASS (no warnings):**
  `"All verification layers passed. Safe to advance phase."`

- **PASS with warnings only (no CRITICAL):**
  `"Minor issues found. Review findings and decide whether to fix now or defer."`

- **Any CRITICAL finding:**
  `"Critical issues found. Fix before advancing. Then re-run /gsd-multi:codex-verify."`

- **Codex INCOMPLETE or SKIPPED, no other issues:**
  `"GSD verification passed. Cross-review unavailable or incomplete. Consider installing/re-running Codex for full coverage."`

**Important:** On FAIL, report only. Show what failed. The user decides the next action. Do NOT auto-generate fix tasks or attempt repairs.

---

## Error Handling Summary

| Scenario | Behavior |
|---|---|
| Codex CLI not installed | Graceful skip with install hint. GSD verification still runs and reports. |
| Codex times out (exit 124) | Report timeout, mark INCOMPLETE, include any partial output. Continue to report. |
| Codex returns non-zero exit | Log error details, mark INCOMPLETE. Continue with report. |
| JSONL parse failure on individual lines | Skip malformed line, log warning, continue parsing remaining lines. |
| Truncated JSONL (no turn.completed event) | Report INCOMPLETE, include whatever was parsed. |
| Missing .planning/ files | Note which files missing, skip that context, continue. |
| /gsd:verify-work fails to run | Report the error, set GSD status to UNKNOWN, note it in report. |
| VERIFICATION.md not found after GSD verify | Warn, set GSD to UNKNOWN, proceed with cross-review. |
| Phase directory missing | Print error and STOP. Cannot proceed without phase context. |
| No git history | Note in report. Cross-review scope limited. |
