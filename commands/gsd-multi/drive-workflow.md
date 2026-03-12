# Drive Workflow -- State Machine and Dispatch Logic

Detailed orchestration logic for `/gsd-multi:drive`. This file is referenced from `drive.md` and contains the full decision tree, dispatch mechanism, drive log, pause detection, and retry logic.

**Anti-patterns -- never do these:**
- Do NOT track state in memory across loop iterations -- always re-read from disk
- Do NOT mention `/clear` to the user -- true autopilot
- Do NOT print verbose output between steps -- banners only
- Do NOT use Skill() for plan/execute/verify -- use Agent() to keep orchestrator context lean

**Context management principle:**
The drive orchestrator must stay under ~15% context. Heavy steps (plan, execute, verify) are dispatched via Agent() so their full output stays in the subagent's context and only a short summary returns. This allows multi-phase drives to complete without context pressure.

---

## Section 1: Determine Target Phases

Based on `TARGET_MODE` from drive.md, resolve the list of phases to drive.

### Auto Mode (no flags)

Read STATE.md current position and find the first incomplete phase:

```bash
STATE_JSON=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" state 2>/dev/null)
ROADMAP_JSON=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" roadmap analyze 2>/dev/null)
```

Parse the current phase number from STATE_JSON. Then scan ROADMAP_JSON for the first phase where `complete` is false. Set `PHASES` to that single phase number.

If all phases are complete: print "All phases complete for this milestone." and stop.

### Single Mode (--phase N)

Check if phase N dependencies are met by examining ROADMAP_JSON:
- All phases numbered less than N must be complete
- If any prerequisite is incomplete, prepend those phases to the list

Set `PHASES` to `[prerequisites..., N]`.

Example: `--phase 3` but phases 1-2 incomplete -> `PHASES=[1, 2, 3]`

### Range Mode (--to N)

Get current phase from STATE_JSON. Set `PHASES` to all phases from current through N (inclusive), filtering out already-complete phases.

Example: current=2, `--to 5`, phase 3 already complete -> `PHASES=[2, 4, 5]`

---

## Section 2: The Drive Loop

For each phase in `PHASES`, execute this loop:

```
1. Print banner: "=== DRIVING PHASE {N}: {name} ==="
2. Set VERIFY_RETRIES=0 for this phase
3. INNER LOOP:
   a. Determine next action (Section 3)
   b. If action is "phase-complete" -> break inner loop, continue to next phase
   c. If action is "done" -> break all loops
   d. If action is "error" -> stop with error message
   e. Dispatch action (Section 4)
   f. Log result to STATE.md (Section 5)
   g. Re-read STATE.md and artifacts from disk
   h. Go to step (a)
4. Increment PHASES_COMPLETED
5. Print banner: "=== PHASE {N} COMPLETE ==="
```

Always re-read state from disk at step (g). Never carry state in memory between iterations.

---

## Section 3: Determine Next Action

Read STATE.md and check artifacts in the current phase directory. Use `gsd-tools.cjs` for state parsing and `ls` for artifact checks.

### Get Phase Directory

```bash
PHASE_INFO=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" init phase-op ${PHASE} 2>/dev/null)
```

Extract `phase_dir` from the JSON output. This gives the full path to `.planning/phases/XX-name/`.

### Artifact Checks

Run these checks against the phase directory:

```bash
CONTEXT_EXISTS=$(ls "$PHASE_DIR"/*-CONTEXT.md 2>/dev/null | wc -l)
RESEARCH_EXISTS=$(ls "$PHASE_DIR"/*-RESEARCH.md 2>/dev/null | wc -l)
PLAN_COUNT=$(ls "$PHASE_DIR"/*-PLAN.md 2>/dev/null | wc -l)
SUMMARY_COUNT=$(ls "$PHASE_DIR"/*-SUMMARY.md 2>/dev/null | wc -l)
VERIFICATION_EXISTS=$(ls "$PHASE_DIR"/*-VERIFICATION.md 2>/dev/null | wc -l)
UAT_EXISTS=$(ls "$PHASE_DIR"/*-UAT.md 2>/dev/null | wc -l)
```

If UAT exists, read its content to check for PASS/FAIL:
```bash
UAT_CONTENT=$(cat "$PHASE_DIR"/*-UAT.md 2>/dev/null)
UAT_PASS=$(echo "$UAT_CONTENT" | grep -ci "PASS" || echo "0")
UAT_FAIL=$(echo "$UAT_CONTENT" | grep -ci "FAIL" || echo "0")
```

### Decision Table

Evaluate conditions in this exact order (first match wins):

| # | Condition | Action | Notes |
|---|-----------|--------|-------|
| 1 | `CONTEXT_EXISTS == 0` | `discuss` | No context gathered yet |
| 2 | `CONTEXT_EXISTS > 0` AND research enabled AND `RESEARCH_EXISTS == 0` | `research` | Config flag: `workflow.research` |
| 3 | `CONTEXT_EXISTS > 0` AND `PLAN_COUNT == 0` | `plan` | Context exists, no plans created |
| 4 | `PLAN_COUNT > 0` AND `SUMMARY_COUNT < PLAN_COUNT` | `execute` | Plans exist, not all executed |
| 5 | `PLAN_COUNT > 0` AND `SUMMARY_COUNT >= PLAN_COUNT` AND `UAT_EXISTS == 0` | `verify` | All plans executed, needs verification |
| 6 | `UAT_EXISTS > 0` AND `UAT_PASS > 0` | `transition` | Verification passed |
| 7 | `UAT_EXISTS > 0` AND `UAT_FAIL > 0` AND `VERIFY_RETRIES < 2` | `retry-verify` | Verification failed, retries remaining |
| 8 | `UAT_EXISTS > 0` AND `UAT_FAIL > 0` AND `VERIFY_RETRIES >= 2` | `error` | Verification failed, no retries left |
| 9 | All artifacts exist and phase marked complete in roadmap | `phase-complete` | Phase is done |

Check the research config flag:
```bash
RESEARCH_ENABLED=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-get workflow.research 2>/dev/null || echo "false")
```

---

## Section 4: Dispatch Action

Heavy steps (plan, execute, verify) are dispatched via Agent() to keep the orchestrator's context lean. Light steps (discuss, transition) run inline since they produce minimal output.

### discuss

When `/gsd-multi:drive` needs context for a phase, generate a minimal CONTEXT.md directly instead of running discuss-phase interactively. This avoids user prompts during autonomous driving.

**Steps:**

1. Read the phase description from ROADMAP.md:
   ```bash
   PHASE_SECTION=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" roadmap get-phase "${PHASE}")
   ```

2. Write a minimal CONTEXT.md with all decisions marked as Claude's Discretion:
   ```markdown
   # Phase {PHASE}: {Name} - Context

   **Gathered:** {date}
   **Status:** Ready for planning
   **Source:** Auto-generated by /gsd-multi:drive (no user discussion)

   <domain>
   ## Phase Boundary

   {Phase goal from ROADMAP.md}

   </domain>

   <decisions>
   ## Implementation Decisions

   ### Claude's Discretion
   All implementation decisions deferred to Claude's judgment.
   /gsd-multi:drive auto-generated this context -- no user discussion occurred.
   Research and planning agents should make reasonable default choices.

   </decisions>

   <specifics>
   ## Specific Ideas

   No specific requirements -- open to standard approaches

   </specifics>

   <deferred>
   ## Deferred Ideas

   None -- auto-generated context

   </deferred>

   ---

   *Phase: {padded_phase}-{slug}*
   *Context gathered: {date} via /gsd-multi:drive*
   ```

3. Commit the context:
   ```bash
   node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" commit "docs(${PADDED_PHASE}): auto-generate context via /gsd-multi:drive" --files "${PHASE_DIR}/${PADDED_PHASE}-CONTEXT.md"
   ```

4. Continue to next action (loop back to Section 3).

### research

Dispatched via Agent() to contain research output.

```
Agent(
  subagent_type="general-purpose",
  description="Research Phase {PHASE}",
  prompt="Run /gsd:research-phase {PHASE}. Return only: research file path and a 2-line summary of findings."
)
```

Only dispatched when `workflow.research` is enabled in config.json.

### plan

Dispatched via Agent() -- planning produces large plan files and checker output that would fill the orchestrator's context.

```
Agent(
  subagent_type="general-purpose",
  description="Plan Phase {PHASE}",
  prompt="Run /gsd:plan-phase {PHASE}. Return only: number of plans created, wave structure, and verification result (PASSED/FAILED/iterations)."
)
```

### execute

Dispatched via Agent() -- execution is the heaviest step, spawning its own subagents per plan.

```
Agent(
  subagent_type="general-purpose",
  description="Execute Phase {PHASE}",
  prompt="Run /gsd:execute-phase {PHASE}. Return only: plans completed (N/M), total tests passing, and any failures or blockers."
)
```

Increment `PLANS_EXECUTED` by the number of plans executed (check SUMMARY count delta after return).

### verify

Dispatched via Agent() -- verification reads all source files and produces detailed reports.

```
Agent(
  subagent_type="general-purpose",
  description="Verify Phase {PHASE}",
  prompt="Run /gsd:verify-work {PHASE}. Return only: verification status (PASSED/FAILED/gaps_found), score (N/M must-haves), and any gap summaries."
)
```

### retry-verify

Handle verification failure with retry:

1. Increment `VERIFY_RETRIES`
2. Delete the existing UAT.md to allow re-verification:
   ```bash
   rm -f "$PHASE_DIR"/*-UAT.md
   ```
3. Run gap closure via Agent():
   ```
   Agent(
     subagent_type="general-purpose",
     description="Gap closure Phase {PHASE}",
     prompt="Run /gsd:execute-phase {PHASE} --gaps-only. Return only: plans completed and test results."
   )
   ```
4. Re-run verification via Agent():
   ```
   Agent(
     subagent_type="general-purpose",
     description="Re-verify Phase {PHASE}",
     prompt="Run /gsd:verify-work {PHASE}. Return only: verification status and score."
   )
   ```

### transition

Runs inline (minimal context cost):

```
Skill(skill="gsd:transition", args="${PHASE}")
```

After transition completes, the phase is done. Continue to next phase in PHASES list.

### After Every Dispatch

After each Agent() or Skill() call completes:
1. Re-read STATE.md and all artifacts from disk
2. Do NOT rely on return values for state -- always check disk
3. Use the artifact checks from Section 3 to determine the outcome
4. Log the result (Section 5)

---

## Section 5: Drive Log

After each action completes, append a log entry to STATE.md.

### Log Format

The drive log is a table appended to the end of STATE.md:

```markdown
## Drive Log

| Timestamp | Phase | Step | Result |
|-----------|-------|------|--------|
```

### Appending Entries

1. Get timestamp:
   ```bash
   TIMESTAMP=$(node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" current-timestamp 2>/dev/null)
   ```

2. Read STATE.md content
3. Check if "## Drive Log" section exists
   - If not: append the header and table header
   - If yes: append just the new row

4. Write updated STATE.md

Entry format:
```
| {TIMESTAMP} | {PHASE} | {step_name} | {result} |
```

Result values: `complete`, `complete (N plans)`, `PASS`, `FAIL (retry N)`, `error: {message}`

---

## Section 6: Pause Detection

The orchestrator pauses ONLY when absolutely necessary.

### Pause Triggers (stop and inform user)

- A `checkpoint:human-action` task is encountered during execute-phase (deploy, configure API key, create account)
- An unrecoverable error occurs (2 verification retries exhausted)
- A Skill() call fails with an error that cannot be auto-resolved

### Never Pause For

- Design decisions -- auto-decide per locked decisions in CONTEXT.md
- Technical choices -- Claude picks the best option
- Verification warnings -- proceed unless FAIL verdict
- Ambiguous requirements -- use reasonable defaults
- Context window pressure -- trust Claude Code compaction

### When Pausing

Record the resume point so the next invocation can continue:

```bash
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" state record-session \
  --stopped-at "Phase ${PHASE} - awaiting user action" \
  --resume-file ".planning/phases/${PHASE_DIR}/"
```

Print a clear message:
```
=== GSD DRIVE PAUSED ===

Phase: {N} ({name})
Step: {current_step}
Reason: {why_paused}

Action needed: {what_user_must_do}

Resume: Run /gsd-multi:drive to continue from this point.
```

---

## Section 7: Verification Retry Logic

Track retry count as a local variable per phase. Initialize `VERIFY_RETRIES=0` at the start of each phase.

### On Verification Failure (UAT.md with FAIL)

1. Increment `VERIFY_RETRIES`
2. Log the failure to drive log: `FAIL (retry {VERIFY_RETRIES})`
3. If `VERIFY_RETRIES < 2`:
   - Remove the failed UAT.md
   - Run gap closure: `Skill(skill="gsd:execute-phase", args="${PHASE} --gaps-only")`
   - Re-run verification: `Skill(skill="gsd:verify-work", args="${PHASE}")`
   - Re-read UAT.md from disk to check result
4. If `VERIFY_RETRIES > 2`:
   - Log to drive log: `error: verification failed after 2 retries`
   - Print error message:
     ```
     Verification failed after 2 retries for Phase {N}.
     Manual intervention needed.
     Run /gsd:verify-work {N} to diagnose.
     ```
   - Record session and stop

---

## Section 8: Phase Completion and Cross-Phase Advance

### After Transition Completes

1. Print banner: `=== PHASE {N} COMPLETE ===`
2. Increment `PHASES_COMPLETED`
3. Check if more phases remain in `PHASES` list:
   - If yes: continue to next phase (go back to Section 2 loop)
   - If no: proceed to final summary (Step 5 in drive.md)

### Cross-Phase State

Between phases, always re-read:
- STATE.md (position may have advanced)
- ROADMAP.md (completion status updated by transition)

Never carry phase-specific state (VERIFY_RETRIES, artifact counts) across phase boundaries. Reset all counters at the start of each phase.

### All Phases Complete

When all targeted phases are done:
1. Clear the auto-chain flag:
   ```bash
   node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set workflow._auto_chain_active false
   ```
2. Return to drive.md Step 5 for final summary output
