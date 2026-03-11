---
name: gsd-drive
description: Auto-drive the full GSD workflow — chains discuss, plan, execute, verify, and advance for one or more phases without manual intervention
argument-hint: "[--phase N] [--to N]"
allowed-tools: Read, Write, Bash, Glob, Grep, Task
---

# /gsd:drive — Autonomous Workflow Orchestrator

Drive the full GSD lifecycle (discuss -> plan -> execute -> verify -> advance) for one or more phases. Single entry point that replaces manual step-by-step invocation.

---

## Step 1: Parse Arguments

Extract targeting mode from `$ARGUMENTS`:

```
TARGET_MODE = "auto"    # default
TARGET_PHASE = ""
TARGET_TO = ""
```

**Parse rules:**
- No flags -> `TARGET_MODE="auto"` (detect from STATE.md)
- `--phase N` -> `TARGET_MODE="single"`, `TARGET_PHASE=N`
- `--to N` -> `TARGET_MODE="range"`, `TARGET_TO=N`
- Both `--phase N --to M` -> Error: "Use --phase for a single phase or --to for a range, not both."

Extract values:
```bash
# Parse from $ARGUMENTS
PHASE_FLAG=$(echo "$ARGUMENTS" | grep -oP '(?<=--phase\s)\d+' || echo "")
TO_FLAG=$(echo "$ARGUMENTS" | grep -oP '(?<=--to\s)\d+' || echo "")
```

If `PHASE_FLAG` is set and `TO_FLAG` is set: print error and stop.
If `PHASE_FLAG` is set: `TARGET_MODE="single"`, `TARGET_PHASE=$PHASE_FLAG`.
If `TO_FLAG` is set: `TARGET_MODE="range"`, `TARGET_TO=$TO_FLAG`.

## Step 2: Validate Environment

Check that a GSD project exists:

```bash
[ -f ".planning/STATE.md" ] && [ -f ".planning/ROADMAP.md" ] && echo "OK" || echo "MISSING"
```

If `MISSING`: print "No GSD project found. Run /gsd:new-project first." and **stop**.

## Step 3: Initialize Drive State

```bash
VERIFY_RETRIES=0
PHASES_COMPLETED=0
PLANS_EXECUTED=0
```

Read current state:
```bash
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" state
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" roadmap analyze
```

Set the `_auto_chain_active` flag so sub-skills know they are being driven:
```bash
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set workflow._auto_chain_active true
```

## Step 4: Execute Drive Loop

Follow the detailed state machine and dispatch logic defined in:

@skills/gsd-drive/drive-workflow.md

Execute the drive loop from `drive-workflow.md` using `TARGET_MODE`, `TARGET_PHASE`, and `TARGET_TO` as inputs. The workflow file contains:
- Target phase resolution (auto/single/range)
- The main drive loop (determine action -> dispatch -> log -> repeat)
- Artifact-based next-action determination
- Skill() dispatch for each workflow step
- Drive log management
- Pause detection and verification retry logic

## Step 5: Final Summary

After the drive loop completes (all targeted phases done or stopped), print:

```
=== GSD DRIVE COMPLETE ===

Phases completed: {PHASES_COMPLETED}
Plans executed: {PLANS_EXECUTED}
Verification retries: {VERIFY_RETRIES}

Drive log written to STATE.md
```

If there are remaining incomplete phases in ROADMAP.md:
```
Next: Run /gsd:drive to continue with Phase {next_incomplete}
```

If all phases complete:
```
All phases complete for this milestone.
Run /gsd:new-milestone to plan your next milestone.
```

Clear the auto-chain flag:
```bash
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set workflow._auto_chain_active false
```
