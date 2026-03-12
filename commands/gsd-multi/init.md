---
name: gsd-multi:init
description: Bootstrap a new project with the GSD + Claude Code + Codex dual-tool workflow. Creates AGENTS.md, CLAUDE.md, .claude/rules/, Codex config, and initializes GSD.
argument-hint: [project-name] [--force]
allowed-tools: Read, Write, Bash, Glob
---

# Initialize GSD + Dual-Tool Workflow

Bootstrap the current directory as a fully harnessed GSD project with Claude Code + Codex integration. This skill is idempotent: safe to re-run on existing projects. Existing files are preserved unless `--force` is passed.

Follow every step below in order. Track two lists throughout: `created_files` and `skipped_files`. Every file operation must report what it did (created, skipped, or overwrote). Never fail silently.

---

## Step 1: Parse arguments and detect environment

1. Check `$ARGUMENTS` for input:
   - If `$ARGUMENTS` contains a project name (first non-flag word), use it as `PROJECT_NAME`
   - Otherwise, detect project name from the current directory basename via Bash: `basename "$PWD"`
   - Check if `--force` flag is present in `$ARGUMENTS`. If present, set `FORCE=true`; otherwise `FORCE=false`

2. Initialize tracking lists (keep these in memory throughout):
   ```
   created_files=[]
   skipped_files=[]
   global_status=[]
   ```

3. Detect and initialize git:
   ```bash
   if [ ! -d ".git" ]; then
     git init
   fi
   ```
   - If `git init` fails, report: "WARNING: git init failed. Continuing without git." and proceed with remaining steps.
   - If `.git/` already exists, do nothing (already initialized).

## Step 2: Stack detection

Detect the project's technology stack by reading config files. Store results in `STACK_BUILD`, `STACK_TEST`, and `STACK_DEV` variables for use in AGENTS.md.

Check each file in order. Use the **first match** as the primary stack, but collect all detected stacks:

**2a. Node.js -- check for `package.json`:**

Use the Read tool to read `package.json`. If it exists:
- Extract `scripts.build` value (e.g., `npm run build`, `tsc`, `vite build`)
- Extract `scripts.test` value (e.g., `npm test`, `jest`, `vitest`)
- Extract `scripts.dev` value (e.g., `npm run dev`, `next dev`)
- Set `STACK_BUILD`, `STACK_TEST`, `STACK_DEV` from these values
- If scripts section is missing or empty, use: `npm run build`, `npm test`, `npm run dev`

**2b. Python -- check for `pyproject.toml`:**

Use the Read tool to read `pyproject.toml`. If it exists:
- Look for `[tool.pytest]` or `[tool.pytest.ini_options]` to detect pytest
- Look for `[build-system]` to detect build tool (setuptools, poetry, hatch, etc.)
- Set `STACK_BUILD` based on build-system (e.g., `pip install -e .`, `poetry build`, `hatch build`)
- Set `STACK_TEST` to `pytest` if detected, otherwise `python -m pytest`
- Set `STACK_DEV` to `python -m <module>` or leave as placeholder

**2c. Makefile -- check for `Makefile`:**

Use the Read tool to read `Makefile`. If it exists:
- Look for targets: `build`, `test`, `run`, `dev`, `all`
- Set `STACK_BUILD` to `make build` (or `make` if only `all` target found)
- Set `STACK_TEST` to `make test` if target exists
- Set `STACK_DEV` to `make run` or `make dev` if target exists

**2d. Go -- check for `go.mod`:**

Use the Read tool to read `go.mod`. If it exists:
- Extract module name from `module` line
- Set `STACK_BUILD` to `go build ./...`
- Set `STACK_TEST` to `go test ./...`
- Set `STACK_DEV` to `go run .`

**2e. Rust -- check for `Cargo.toml`:**

Use the Read tool to read `Cargo.toml`. If it exists:
- Extract package name from `[package]` section
- Set `STACK_BUILD` to `cargo build`
- Set `STACK_TEST` to `cargo test`
- Set `STACK_DEV` to `cargo run`

**2f. No stack detected:**

If none of the above files exist, set:
- `STACK_BUILD` to `# TODO: Add build command`
- `STACK_TEST` to `# TODO: Add test command`
- `STACK_DEV` to `# TODO: Add dev/run command`

## Step 3: Create AGENTS.md

**Idempotency check:** Use the Read tool to check if `AGENTS.md` exists.

- If `AGENTS.md` exists AND `FORCE` is `false`: add `AGENTS.md` to `skipped_files` with reason "already exists". Skip to Step 4.
- If `AGENTS.md` does not exist OR `FORCE` is `true`: create the file using the Write tool and add to `created_files`.

Write `AGENTS.md` with this content (substitute `PROJECT_NAME` and stack detection results):

```markdown
# PROJECT_NAME

## Build & Test

- **Build:** STACK_BUILD
- **Test:** STACK_TEST
- **Dev:** STACK_DEV

## Architecture

- `src/` -- Source code
- `tests/` -- Test files
- `.planning/` -- GSD state (do not manually edit during execution phases)

## Conventions

- Write tests for all new features
- No debug/log statements in production code
- Keep functions small and focused
- Each commit should be atomic and revertable
- Skills must work across Claude Code sessions without re-explaining
- All instruction files must stay under 200 lines for >92% rule adherence

## Workflow

This project uses GSD spec-driven development with dual-tool execution:
1. All planning state lives in `.planning/`
2. Check `.planning/STATE.md` for current workflow position
3. Follow the loop: discuss > plan > execute > verify
4. During execution, split tasks by complexity:
   - Claude Code: complex multi-file changes, architecture, interactive debugging
   - Codex: autonomous tasks, CRUD, tests, scripts, CLI tools, CI/CD
   - Use git worktrees to run both in parallel
5. Cross-review: each tool reviews the OTHER's output
6. Each task produces a separate atomic git commit
```

## Step 4: Create CLAUDE.md

**Idempotency check:** Use the Read tool to check if `CLAUDE.md` exists.

- If `CLAUDE.md` exists AND `FORCE` is `false`: add `CLAUDE.md` to `skipped_files` with reason "already exists". Skip to Step 5.
- If `CLAUDE.md` does not exist OR `FORCE` is `true`: create the file using the Write tool and add to `created_files`.

Write `CLAUDE.md` with this content (substitute `PROJECT_NAME`):

```markdown
# PROJECT_NAME -- Claude Code Instructions

See @AGENTS.md for build commands, architecture, and conventions.

## GSD Workflow

- Run `/gsd:status` at the start of every session to orient yourself
- Follow: `/gsd:discuss-phase` > `/gsd:plan-phase` > `/gsd:execute-phase` > `/gsd:verify-work`
- Use subagents strategically: haiku for research, sonnet for implementation, opus for planning/review

## Dual-Tool Execution

During execute phase, split tasks by complexity:
- Claude Code: complex multi-file changes, architecture, interactive work
- Codex (in parallel worktree): autonomous tasks, CRUD, tests, scripts, CLI tools
- Run `codex --full-auto "task description"` in a separate worktree for autonomous work

## Dual-Tool Verification (Cross-Review)

After execution, each tool reviews the OTHER's work:
- Run `/gsd-multi:codex-verify` for combined verification
- Claude verifies Codex's autonomous output against specs
- Codex reviews Claude's complex changes for blind spots
Only advance phases after both verification layers pass.

## Quality Gates

- Never skip verification
- If verification fails, fix in a new task -- do not patch inline
- Every task = one atomic commit
```

## Step 5: Create .claude/rules/ directory and rule files

First, ensure the directory exists:

```bash
mkdir -p .claude/rules
```

Create each rule file below with its own idempotency check:

### 5a. gsd-workflow.md (always active, no path frontmatter)

**Idempotency check:** Use the Read tool to check if `.claude/rules/gsd-workflow.md` exists.

- If exists AND `FORCE` is `false`: add to `skipped_files`. Skip.
- Otherwise: create with the Write tool, add to `created_files`.

Content:

```markdown
When working on this project, follow the GSD dual-tool workflow:
1. Check /gsd:status before making changes
2. If .planning/STATE.md exists, respect the current phase position
3. During execution, handle complex/interactive tasks -- suggest autonomous tasks for Codex
4. Each task must produce an atomic, revertable git commit
5. After execution, run /gsd-multi:codex-verify for cross-review (each tool reviews the other's work)
```

### 5b. planning-files.md (activates on .planning/**)

**Idempotency check:** Same pattern as above.

Content:

```yaml
---
paths:
  - ".planning/**"
---
```
```markdown
GSD state files. Rules:
- STATE.md tracks current position -- read it to orient
- PLAN.md files contain XML tasks -- execute in wave order
- REQUIREMENTS.md is the source of truth for deliverables
- Never modify outside of GSD commands (/gsd:*)
```

### 5c. test-files.md (activates on test files)

**Idempotency check:** Same pattern as above.

Content:

```yaml
---
paths:
  - "tests/**"
  - "**/*.test.*"
  - "**/*.spec.*"
---
```
```markdown
Test file rules:
- Every new feature needs tests
- Run full test suite before marking a task complete
- Tests must pass before /gsd:verify-work
```

### 5d. security.md (activates on sensitive files)

**Idempotency check:** Same pattern as above.

Content:

```yaml
---
paths:
  - "**/*.env*"
  - "**/auth/**"
  - "**/config/**"
---
```
```markdown
Security-sensitive file. Never commit secrets or API keys. Validate external input. Flag concerns during verification.
```

## Step 6: Create .claude/modes/ directory and mode files

First, ensure the directory exists:

```bash
mkdir -p .claude/modes
```

### 6a. ideate.md

**Idempotency check:** Use the Read tool to check if `.claude/modes/ideate.md` exists.

- If exists AND `FORCE` is `false`: add to `skipped_files`. Skip.
- Otherwise: create with the Write tool, add to `created_files`.

Content:

```markdown
---
description: "Brainstorm with full project context"
skills: []
rules: []
---

# Ideate Mode

**Name:** Ideate
**Description:** Brainstorm with full project context

## Session Start

Silently read these files (if they exist) -- don't narrate, just internalize:
- `.planning/PROJECT.md`
- `.planning/MILESTONES.md`
- `.planning/RETROSPECTIVE.md`
- `.planning/STATE.md`

Then greet briefly: "Context loaded. What are you thinking about?"

If none of the files exist: "No project context found. We can brainstorm from scratch -- what's the idea?"

## Role

You are a creative thinking partner who knows what the user has built, what worked, what didn't, and what's been deferred.

- Explore ideas freely -- no premature structure
- Ask "what if" questions to expand thinking
- Connect new ideas to existing project context (shipped features, known gaps, deferred work)
- Challenge assumptions when useful
- Keep the energy generative, not critical

## What NOT To Do

- No GSD commands (/status, /switch, /run, /execute)
- No scaffolding or file creation
- No project planning or phase breakdowns
- Don't volunteer to build anything -- this is thinking time

## When Ideas Solidify

When an idea feels ready to act on, suggest:

"This sounds ready. Start a new session and run `/gsd:new-milestone` to turn it into a plan."

Don't push this -- only suggest when the user signals they want to move forward.

## Mode Boundaries

If a user types GSD commands: respond with "That's a GSD command. Start a new session in GSD mode to use it."
```

## Step 7: Global Codex config (one-time)

### 7a. Codex config.toml

**Check existence:**

```bash
[ -f "$HOME/.codex/config.toml" ] && echo "EXISTS" || echo "MISSING"
```

- If `EXISTS` AND `FORCE` is `false`: add to `global_status` as "~/.codex/config.toml: skipped (already exists)". Report: "Existing ~/.codex/config.toml found. Skipping. (Use --force to overwrite.)"
- If `MISSING` OR `FORCE` is `true`:
  1. Create directory: `mkdir -p ~/.codex`
  2. Use the Write tool to create `~/.codex/config.toml` with:

```toml
model = "gpt-5-codex"
approval_policy = "untrusted"
sandbox_mode = "workspace-write"
project_doc_fallback_filenames = ["CLAUDE.md", "COPILOT.md"]

[profiles.review]
model = "gpt-5-codex"
approval_policy = "untrusted"
sandbox_mode = "read-only"
```

  3. Add to `global_status` as "~/.codex/config.toml: created".

### 7b. Codex AGENTS.md

**Check existence:**

```bash
[ -f "$HOME/.codex/AGENTS.md" ] && echo "EXISTS" || echo "MISSING"
```

- If `EXISTS` AND `FORCE` is `false`: add to `global_status` as "~/.codex/AGENTS.md: skipped (already exists)".
- If `MISSING` OR `FORCE` is `true`:
  1. Create directory if needed: `mkdir -p ~/.codex`
  2. Use the Write tool to create `~/.codex/AGENTS.md` with:

```markdown
# Global Codex Instructions

You are an autonomous coder and cross-reviewer in a dual-tool workflow with Claude Code + GSD.

## When Coding (autonomous tasks)

- Read AGENTS.md and .planning/PLAN.md for task specs before starting
- Focus on well-defined tasks: CRUD endpoints, tests, scripts, CLI tools, CI/CD, bug fixes
- Work autonomously -- deliver complete, tested implementations
- Make atomic, revertable commits per task
- Run tests before committing

## When Reviewing (cross-review of Claude's work)

- Check `.planning/REQUIREMENTS.md` for expected behavior
- Check `.planning/STATE.md` for current workflow position
- Focus on: bugs, security vulnerabilities, missing test coverage, edge cases
- Flag anything that deviates from `.planning/` specs
- Report findings with severity: CRITICAL / WARNING / INFO

## Rules

- Follow the project AGENTS.md for coding standards
- Make atomic, revertable commits
- Never modify `.planning/` state files -- those are managed by GSD via Claude Code
- Verify your work passes existing tests before committing
```

  3. Add to `global_status` as "~/.codex/AGENTS.md: created".

## Step 8: Global Claude preferences (one-time)

**Check existence:**

```bash
[ -f "$HOME/.claude/CLAUDE.md" ] && echo "EXISTS" || echo "MISSING"
```

**If `EXISTS`:**
1. Use the Read tool to read `~/.claude/CLAUDE.md`
2. Search for "GSD Workflow" in the content
3. If "GSD Workflow" section is already present: add to `global_status` as "~/.claude/CLAUDE.md: skipped (GSD section already present)". Skip.
4. If "GSD Workflow" section is NOT present: APPEND (do NOT overwrite) the following to the end of the file using the Write tool (read existing content first, then write existing + new):

```markdown

## GSD Workflow

- I use GSD for all non-trivial work
- Check for /gsd:status and .planning/ at session start
- After GSD verification, cross-validate with Codex
```

5. Add to `global_status` as "~/.claude/CLAUDE.md: updated (appended GSD section)".

**If `MISSING`:**
1. Create directory if needed: `mkdir -p ~/.claude`
2. Use the Write tool to create `~/.claude/CLAUDE.md` with:

```markdown
# Global Preferences

## GSD Workflow

- I use GSD for all non-trivial work
- Check for /gsd:status and .planning/ at session start
- After GSD verification, cross-validate with Codex
```

3. Add to `global_status` as "~/.claude/CLAUDE.md: created".

## Step 9: Install GSD framework

**Check if GSD is already installed:**

```bash
if [ -d "$HOME/.claude/commands/gsd" ] || [ -d "$HOME/.claude/get-shit-done" ]; then
  echo "INSTALLED"
else
  echo "NOT_INSTALLED"
fi
```

- If `INSTALLED`: add to `global_status` as "GSD framework: already installed". Skip.
- If `NOT_INSTALLED`:
  1. Run: `npx get-shit-done-cc@latest`
  2. If the command succeeds: add to `global_status` as "GSD framework: installed".
  3. If the command fails: report the error and add to `global_status` as "GSD framework: FAILED to install". Print:
     ```
     WARNING: GSD framework installation failed.
     Manual install: npx get-shit-done-cc@latest
     You can continue without GSD, but /gsd:* commands will not be available.
     ```
     Continue with remaining steps (do not abort).

## Step 10: Update .gitignore

1. Use the Read tool to check if `.gitignore` exists.
2. If it does not exist, create it with the Write tool containing:

```
.claude/settings.local.json
```

3. If it exists, read its contents and check if `.claude/settings.local.json` is already listed.
   - If already present: do nothing.
   - If NOT present: append `.claude/settings.local.json` to the end of the file (read existing content, add a newline if needed, then append the pattern). Use the Write tool with the full updated content.

4. Add `.gitignore` to `created_files` (if new) or note "updated" (if appended).

## Step 11: Print summary

After all steps complete, print a formatted summary. Use the tracked lists to build the output:

```
=== GSD Project Initialized ===

Project: PROJECT_NAME

Created:
  [list each file from created_files, one per line, with description]
  Example:
    AGENTS.md              -- Universal instructions (Claude + Codex)
    CLAUDE.md              -- Claude workflow + GSD commands
    .claude/rules/         -- Auto-activating context rules (N files)
    .claude/modes/         -- Session modes (N files)

Skipped (already exist):
  [list each file from skipped_files, one per line]
  Example:
    AGENTS.md              -- already exists (use --force to overwrite)

Global config:
  [list each item from global_status]
  Example:
    ~/.codex/config.toml   -- created
    ~/.codex/AGENTS.md     -- skipped (already exists)
    ~/.claude/CLAUDE.md    -- updated (appended GSD section)
    GSD framework          -- already installed

Next steps:
  /gsd:new-project         -- Initialize GSD planning for this project
  /gsd:discuss-phase       -- Start your first phase
  /gsd-multi:drive         -- Auto-drive the full GSD workflow (discuss -> plan -> execute -> verify -> advance)

After each phase:
  /gsd-multi:codex-review  -- Cross-model validation with Codex
```

End with this prompt:

```
Run /gsd:new-project now to initialize GSD planning? (Recommended for new projects)
```

---

## Error Handling Summary

These rules apply throughout ALL steps above:

1. **File write failures:** If any Write tool call fails, report which file failed and why. Add to `created_files` as "FAILED: filename (reason)". Continue with next file.
2. **Read failures on detection files:** If reading package.json, pyproject.toml, etc. fails (file not found), that is normal -- it means that stack is not present. Move to next detection check.
3. **Directory creation failures:** If `mkdir -p` fails, report the error. This likely means a permissions issue. Continue with remaining steps.
4. **Git init failure:** Report warning, continue. The project can still be bootstrapped without git.
5. **GSD install failure:** Report warning with manual install command, continue. The project files are still created.
6. **Global config directory issues:** If `~/.claude/` or `~/.codex/` cannot be created, report: "WARNING: Cannot create [dir]. Check permissions. Skipping global config." Continue.
7. **Never leave partial state:** Every step is independent. If step N fails, steps N+1 through 10 still execute. The summary in Step 10 reports all successes and failures.
