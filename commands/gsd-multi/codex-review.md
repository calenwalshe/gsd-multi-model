---
name: gsd-multi:codex-review
description: Run cross-model review using Codex CLI. In the dual-tool workflow, Codex reviews Claude's complex work while Claude reviews Codex's autonomous output. This skill triggers Codex to review whatever Claude built.
argument-hint: [--commits=N] [focus-area]
allowed-tools: Read, Bash, Glob, Grep
---

# Cross-Model Review with Codex

Run Codex CLI to review code changes. In the dual-coder workflow:
- Codex reviews what Claude built (complex multi-file changes)
- Claude reviews what Codex built (autonomous tasks)

This skill handles both directions -- sending Claude's work to Codex AND reviewing Codex's work with Claude.

Execute the following steps IN ORDER. Do not skip steps. Handle all error conditions as specified.

---

## Step 1: Parse Arguments

Parse `$ARGUMENTS` to extract configuration options and focus area.

```bash
# Extract --commits=N if present (default: 5)
COMMIT_COUNT=5
if echo "$ARGUMENTS" | grep -qoP '\-\-commits=\d+'; then
  COMMIT_COUNT=$(echo "$ARGUMENTS" | grep -oP '(?<=--commits=)\d+')
fi

# Everything else (after stripping --commits=N) is the focus area
FOCUS_AREA=$(echo "$ARGUMENTS" | sed 's/--commits=[0-9]*//g' | xargs)
if [ -z "$FOCUS_AREA" ]; then
  FOCUS_AREA="general code quality review"
fi
```

Store `COMMIT_COUNT` and `FOCUS_AREA` for later steps.

---

## Step 2: Check Codex Availability

Detect whether Codex CLI is installed.

```bash
command -v codex >/dev/null 2>&1
```

- **If Codex is NOT installed:**
  - Print: `WARNING: Codex CLI not installed. Skipping cross-model review.`
  - Print: `Install with: npm install -g codex-cli`
  - Print: `Proceeding with Claude-only review of any Codex-built code.`
  - Set `CODEX_AVAILABLE=false`
- **If Codex IS installed:**
  - Set `CODEX_AVAILABLE=true`
  - Print: `Codex CLI detected. Cross-model review enabled.`

---

## Step 3: Read Timeout Configuration

Read the Codex timeout from project configuration.

```bash
cat .planning/config.json 2>/dev/null
```

- Extract the value at `codex.timeout_seconds` from the JSON.
- If the key is missing or `.planning/config.json` does not exist, default to `300` (5 minutes).
- Store as `TIMEOUT_SECONDS`.

---

## Step 4: Gather Review Context

Collect all relevant context for the review. Handle missing files gracefully.

### 4a. Read planning state

Use the Read tool for each of these. If a file does not exist, note it and continue.

- `.planning/STATE.md` -- current phase and position
- `.planning/REQUIREMENTS.md` -- expected behavior and acceptance criteria

### 4b. Get change summary

First, check available commit count to avoid errors:

```bash
AVAILABLE_COMMITS=$(git rev-list --count HEAD 2>/dev/null || echo "0")
```

If `AVAILABLE_COMMITS` is 0, print `No git history found. Nothing to review.` and exit cleanly.

If `AVAILABLE_COMMITS` < `COMMIT_COUNT`, adjust: `COMMIT_COUNT=$AVAILABLE_COMMITS`.

Then gather the diff:

```bash
git diff HEAD~${COMMIT_COUNT} --stat
```

If the diff is empty, print `No changes found in last ${COMMIT_COUNT} commits. Nothing to review.` and exit cleanly.

Get the full diff:

```bash
git diff HEAD~${COMMIT_COUNT}
```

### 4c. Read existing summaries and verifications

Use Glob to find recent artifacts:

```
.planning/phases/*-*/*-SUMMARY.md
.planning/phases/*-*/*-VERIFICATION.md
```

Read the most recent of each if they exist. Skip if none found.

### 4d. Identify Codex-built changes

Check git log for commits authored or mentioning Codex:

```bash
git log HEAD~${COMMIT_COUNT}..HEAD --oneline --all --author="codex" 2>/dev/null || true
git log HEAD~${COMMIT_COUNT}..HEAD --oneline --all --grep="codex" --grep="\[codex\]" --grep="Codex" 2>/dev/null || true
```

Store any matching commits for Step 6. If no Codex commits found, note `CODEX_COMMITS_FOUND=false`.

---

## Step 5: Build and Run Codex Review (if available)

**Only execute this step if `CODEX_AVAILABLE=true`.** Otherwise, skip to Step 6.

### 5a. Construct the review prompt

Build a review prompt that includes:

1. **Project requirements summary** -- key points from REQUIREMENTS.md (not the full file)
2. **Current phase context** -- phase name, position, status from STATE.md
3. **Focus area** -- the `FOCUS_AREA` from Step 1
4. **The diff output** -- full diff from Step 4b
5. **Review checklist:**
   - Bugs and logic errors
   - Security vulnerabilities (OWASP top 10)
   - Missing test coverage for new code paths
   - Edge cases and error conditions not handled
   - Convention violations per AGENTS.md
   - Over-engineering or unnecessary complexity
6. **Required output format:**
   ```
   For each finding, output exactly one of:
   CRITICAL: [description] -- must fix before shipping
   WARNING: [description] -- should fix, not blocking
   INFO: [description] -- suggestion for improvement

   If no issues found, output: PASS -- No issues found.
   ```

### 5b. Execute the Codex review

Run via Bash with timeout:

```bash
timeout ${TIMEOUT_SECONDS} codex exec --full-auto "${REVIEW_PROMPT}" 2>&1
CODEX_EXIT=$?
```

### 5c. Handle Codex result

- **Exit code 0 (success):**
  - Parse stdout for lines starting with `CRITICAL:`, `WARNING:`, or `INFO:`
  - Store as `CODEX_FINDINGS`
  - Set `CODEX_REVIEW_STATUS="PASS"` if no CRITICAL/WARNING, else `"FAIL"`

- **Exit code 124 (timeout):**
  - Print: `WARNING: Codex review timed out after ${TIMEOUT_SECONDS}s. Increase codex.timeout_seconds in .planning/config.json if needed.`
  - Capture any partial output that was produced before timeout
  - Set `CODEX_REVIEW_STATUS="INCOMPLETE"`

- **Any other non-zero exit code:**
  - Print: `WARNING: Codex review failed (exit code ${CODEX_EXIT}). Continuing with Claude-only review.`
  - Print the stderr/stdout for debugging
  - Set `CODEX_REVIEW_STATUS="INCOMPLETE"`

---

## Step 6: Claude Reviews Codex-Built Code (Bidirectional)

This step runs regardless of Codex availability. Claude reviews any code built by Codex.

### 6a. Check for Codex-authored changes

If `CODEX_COMMITS_FOUND=false` from Step 4d:
- Print: `No Codex-built changes found in last ${COMMIT_COUNT} commits.`
- Set `CLAUDE_REVIEW_STATUS="N/A"`
- Skip to Step 7

### 6b. Read Codex-built changes

For each Codex-authored commit found in Step 4d:

```bash
git show ${COMMIT_HASH}
```

### 6c. Review against specifications

Review the Codex-built changes for:

1. **Spec compliance** -- Does the code meet requirements in `.planning/REQUIREMENTS.md`?
2. **Incomplete implementations** -- Are there TODO/FIXME/placeholder patterns?
3. **Missing edge cases** -- Error handling, null checks, boundary conditions?
4. **Test gaps** -- Are there tests for the new functionality?
5. **Architectural mismatches** -- Does the code follow patterns in AGENTS.md?
6. **Security issues** -- Input validation, injection risks, auth checks?

### 6d. Format Claude's findings

Report each finding using the same severity format:

```
CRITICAL: [description] -- must fix before shipping
WARNING: [description] -- should fix, not blocking
INFO: [description] -- suggestion for improvement
```

Set `CLAUDE_REVIEW_STATUS`:
- `"PASS"` if no CRITICAL or WARNING findings
- `"FAIL"` if any CRITICAL findings
- `"WARNING"` if WARNING but no CRITICAL findings

---

## Step 7: Display Combined Results

Format and display the final report. Use this exact structure:

```
=== CROSS-MODEL REVIEW RESULTS ===

Scope: Last {COMMIT_COUNT} commits | Focus: {FOCUS_AREA}

--- Codex reviewed Claude's work: {CODEX_REVIEW_STATUS} ---
{list each finding with severity, or "Codex CLI not available -- skipped" or "No findings"}

--- Claude reviewed Codex's work: {CLAUDE_REVIEW_STATUS} ---
{list each finding with severity, or "No Codex-built changes found in last N commits" or "No findings"}

=== SUMMARY ===
Codex review: {PASS|FAIL|INCOMPLETE|SKIPPED}
Claude review: {PASS|FAIL|WARNING|N/A}
Overall: {verdict}

=== RECOMMENDATION ===
{recommendation}
```

### Recommendation logic:

- **If any CRITICAL findings from either review:**
  `"Critical issues found. Fix before advancing, then re-run /gsd-multi:codex-review."`

- **If WARNING findings but no CRITICAL:**
  `"Minor issues found. Consider fixing before advancing."`

- **If all PASS or N/A:**
  `"Cross-review clean. Safe to advance."`

- **If Codex was INCOMPLETE or SKIPPED and Claude found nothing:**
  `"Codex review unavailable. Claude-only review found no issues. Consider installing Codex CLI for full cross-model coverage."`

---

## Error Handling Summary

| Scenario | Behavior |
|---|---|
| Codex CLI not installed | Graceful skip with install hint. Claude-only review proceeds. |
| Codex times out | Report timeout with config hint. Use any partial output. Continue. |
| Codex returns error | Log error details. Continue with Claude-only review. |
| Fewer commits than requested | Auto-adjust to available commit count. |
| Empty diff (no changes) | Report cleanly and exit. Not an error. |
| .planning/STATE.md missing | Skip state context. Note in output. |
| .planning/REQUIREMENTS.md missing | Skip requirements context. Note in output. |
| .planning/config.json missing | Use default timeout (300s). |
| No Codex-built commits found | Report "N/A" for Claude review of Codex work. |
