---
name: ideate
description: Structured brainstorming with full GSD project context. Produces durable IDEATION.md that feeds into /gsd:new-milestone.
argument-hint: [topic] [--reset]
allowed-tools: Read, Write, Edit, Glob, Bash, AskUserQuestion
---

# GSD Ideate — Structured Brainstorming

Brainstorm ideas with full project awareness. Unlike generic chat, this skill loads your GSD history, connects ideas to what you've built, and produces a durable artifact (`.planning/IDEATION.md`) that bridges directly into `/gsd:new-milestone`.

---

## Step 1: Parse arguments

1. Check `$ARGUMENTS` for:
   - **Topic seed**: first non-flag text (e.g., `/gsd:ideate real-time notifications`). Store as `TOPIC`.
   - **`--reset` flag**: if present, set `RESET=true`. Forces fresh IDEATION.md even if one exists.
2. If no arguments, `TOPIC` is empty and `RESET` is false.

## Step 2: Load GSD context silently

Read each file below **silently** (do not narrate or print contents). Track which exist:

- `.planning/PROJECT.md` — project identity and goals
- `.planning/MILESTONES.md` — shipped and upcoming milestones
- `.planning/RETROSPECTIVE.md` — lessons learned
- `.planning/STATE.md` — current workflow position
- `.planning/ROADMAP.md` — phase breakdown of current milestone

Set `CONTEXT_LEVEL`:
- **full**: PROJECT.md + MILESTONES.md + at least one of RETROSPECTIVE/ROADMAP exist
- **partial**: PROJECT.md exists but missing some files
- **minimal**: PROJECT.md missing or `.planning/` does not exist

## Step 3: Check existing IDEATION.md

Read `.planning/IDEATION.md`. If it exists:

- If `RESET` is true: back up to `.planning/IDEATION.backup-YYYY-MM-DD.md` using Bash, then proceed as fresh start.
- If `RESET` is false: use AskUserQuestion to ask:
  - **"Found existing IDEATION.md. Resume or start fresh?"**
  - Options: "Resume where I left off" / "Start fresh (backup existing)"
  - If "Start fresh": back up and proceed as fresh start.
  - If "Resume": set `RESUMING=true`, load existing ideas.

If IDEATION.md does not exist, proceed as fresh start.

## Step 4: Surface context proactively

Display a brief context card (skip sections where data is missing):

```
--- Project Context ---
Project: [name from PROJECT.md]
Last shipped: [most recent completed milestone from MILESTONES.md]
Top lessons: [1-2 key takeaways from RETROSPECTIVE.md]
Deferred work: [items marked deferred/parking-lot in prior phases]
Current state: [phase position from STATE.md, or "between milestones"]
---
```

If `CONTEXT_LEVEL` is `minimal`, print:
```
No GSD context found. Brainstorming from scratch — ideas will still be captured in IDEATION.md.
```

## Step 5: Open the conversation

Choose one opener based on state:

- **If TOPIC provided**: "Let's explore **[TOPIC]**." Then ask a probing question that connects the topic to project context (if available).
- **If RESUMING**: Summarize existing ideas briefly, then: "Where do you want to pick up?"
- **Otherwise**: "What's been on your mind for the project?" (open-ended, no artificial constraints)

## Step 6: Conversational brainstorm loop

### Your role
You are a **creative thinking partner** who knows this project's history. Your job is to expand possibilities, not narrow them.

### Behaviors
- **Connect to context**: reference shipped features, retrospective lessons, deferred work when relevant
- **Ask "what if" questions** to push ideas further
- **Challenge assumptions** when it opens new directions
- **No scope guardrail**: unlike discuss-phase, ideation should be expansive. Scope is set later at new-milestone time
- **No premature structure**: don't jump to task breakdowns or implementation plans
- Keep energy generative, not critical

### AskUserQuestion usage
Use AskUserQuestion **only** for genuine decision points (e.g., "Should we explore direction A or B deeper?"). Do NOT use it to structure the brainstorm or force choices.

### Incremental writes
After each distinct idea area is explored (roughly every 2-3 exchanges), **update `.planning/IDEATION.md`** with the new content. This ensures ideas survive crashes or context limits. Use the format from Step 7.

## Step 7: Write/update `.planning/IDEATION.md`

Maintain this structure. Update incrementally — append new ideas, refine existing ones:

```markdown
# Ideation

> Status: In Progress
> Date: YYYY-MM-DD
> Project: [project name]
> Last milestone: [most recent shipped milestone]
> Context level: [full/partial/minimal]

## Ideas

### [Idea Area 1]
- **Core concept**: [one-line summary]
- **Details**: [expanded thinking]
- **Connection to history**: [how it relates to shipped work, lessons, or deferred items]
- **Open questions**: [unresolved aspects]

### [Idea Area 2]
...

## Cross-Cutting Themes
- [Patterns that span multiple ideas]

## Parking Lot
- [Ideas set aside for later — not rejected, just not the focus]

## Possible Next Milestones
- [Candidate milestone descriptions that could feed into /gsd:new-milestone]
```

When creating the file for the first time, ensure `.planning/` directory exists:
```bash
mkdir -p .planning
```

## Step 8: Session close

When ideas crystallize or the user signals they're done (e.g., "that's good", "let's wrap up", "I think we have enough"):

1. **Finalize IDEATION.md**: Update the status line to `Status: Ready for /gsd:new-milestone`. Ensure all discussed ideas are captured.

2. **Offer MILESTONE-CONTEXT.md bridge**: Ask via AskUserQuestion:
   - "Want me to write a MILESTONE-CONTEXT.md to fast-track your next `/gsd:new-milestone`?"
   - Options: "Yes, write it" / "No, IDEATION.md is enough"

   If yes, write `.planning/MILESTONE-CONTEXT.md`:
   ```markdown
   # Milestone Context

   > Source: IDEATION.md (YYYY-MM-DD)

   ## Direction
   [The crystallized idea direction from the session]

   ## Key Ideas
   - [Bullet points of the most promising ideas]

   ## Constraints & Considerations
   - [Lessons from retrospective that apply]
   - [Known deferred work to incorporate]

   ## Open Questions for Discovery
   - [Questions that /gsd:new-milestone should explore]
   ```

3. **Print summary**:
   ```
   === Ideation Complete ===
   Ideas captured: [count]
   Possible milestones: [count]
   Artifact: .planning/IDEATION.md

   Next: /gsd:new-milestone to turn ideas into a plan
   ```

---

## Error Handling

- **Missing `.planning/` directory**: create it when first writing IDEATION.md
- **File read failures**: degrade gracefully (reduce CONTEXT_LEVEL, skip that section)
- **Backup failures**: warn but proceed with fresh start anyway
- **Never block on errors**: the brainstorm conversation is the priority
