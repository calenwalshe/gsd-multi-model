# Claude Code Skills & Slash Commands Architecture

**Domain:** Claude Code customization and extensibility framework
**Researched:** 2026-03-02
**Overall Confidence:** HIGH

---

## Executive Summary

Claude Code's custom skills and slash commands form a cohesive extensibility system where skills are the primary mechanism for custom commands. Skills use a directory-based architecture with SKILL.md metadata files (YAML frontmatter + markdown content), and can be stored at multiple scopes (personal, project, plugin, enterprise). Unlike static documentation, skills employ "progressive disclosure" — descriptions load at startup for discovery, full content loads only when invoked. The system supports parameterization via `$ARGUMENTS`, automatic discovery from nested `.claude/skills/` directories, and contextual injection rules for path-specific guidance. Limitations include a dynamic context budget (2% of context window, minimum 16,000 chars) for skill descriptions, 500-line recommendations for SKILL.md bodies, and careful management of nested file references to avoid incomplete reads.

---

## 1. How Claude Code Custom Skills Work

### File Structure & Organization

Skills are directory-based with a required `SKILL.md` file as the entrypoint:

```
my-skill/
├── SKILL.md              # Required: metadata + instructions
├── reference.md          # Optional: detailed API docs
├── examples.md           # Optional: usage examples
├── templates/
│   └── template.md       # Optional: templates Claude fills in
└── scripts/
    ├── validate.py       # Optional: executable utilities
    └── helper.sh         # Optional: helper scripts
```

**SKILL.md Format:**

Every skill needs YAML frontmatter (between `---` markers) followed by markdown content:

```yaml
---
name: my-skill
description: What this skill does and when to use it
disable-model-invocation: true
argument-hint: [argument-format]
allowed-tools: Read, Bash, Write
user-invocable: true
model: opus
context: fork
---

# Skill Instructions

[Markdown content with instructions Claude follows]
```

### Metadata Fields (Frontmatter Reference)

| Field | Required | Type | Purpose |
|-------|----------|------|---------|
| `name` | No* | string | Display name for skill (max 64 chars, lowercase + hyphens only). Defaults to directory name. Becomes the `/slash-command`. |
| `description` | Recommended | string | What skill does + when to use it (max 1024 chars). Used for auto-discovery. Third person required. |
| `argument-hint` | No | string | Hint for autocomplete (e.g., `[issue-number]` or `[filename] [format]`). |
| `disable-model-invocation` | No | boolean | If true, only manual invocation via `/name`. Prevents Claude from triggering automatically. |
| `user-invocable` | No | boolean | If false, hides from `/` menu (only Claude can invoke). For background knowledge. |
| `allowed-tools` | No | array | Tools Claude can use without per-use approval when skill active (e.g., `Read, Grep, Bash`). |
| `model` | No | string | Override model when this skill active. |
| `context` | No | enum | Set to `fork` to run in isolated subagent context. |
| `agent` | No | string | Which subagent type to use when `context: fork` (e.g., `Explore`, `Plan`, `general-purpose`). |
| `hooks` | No | object | Lifecycle hooks scoped to this skill. |

**Critical naming constraint:** Skill names must contain only lowercase letters, numbers, and hyphens (max 64 characters). Cannot contain XML tags or reserved words ("anthropic", "claude").

### Progressive Disclosure & Context Loading

**How skills consume context:**

1. **At startup:** Only skill metadata (name + description) is pre-loaded. ~50-200 tokens per skill.
2. **When Claude decides to use skill:** Full SKILL.md body is injected. ~200-5000 tokens depending on content size.
3. **Supporting files (reference.md, examples.md, etc):** Only loaded when Claude reads them explicitly. Zero context penalty until accessed.
4. **Scripts:** Executed without loading contents. Only output consumes tokens.

This architecture allows hundreds of skills without bloating every conversation. Claude uses descriptions to decide relevance, then loads details on-demand.

**Context budget for descriptions:**

Skill descriptions are loaded into context so Claude knows what's available. If you have many skills, total description tokens may exceed budget:
- **Dynamic budget:** 2% of context window size
- **Fallback minimum:** 16,000 characters
- **Overflow behavior:** If exceeding budget, Claude warns about excluded skills (visible via `/context`)
- **Override:** Set `SLASH_COMMAND_TOOL_CHAR_BUDGET` environment variable to increase

### Storage Locations & Priority

Skills can be stored at multiple scopes. Higher-priority locations override lower:

| Scope | Location | Applies to | Priority |
|-------|----------|-----------|----------|
| Enterprise | `/etc/claude-code/CLAUDE.md` (Linux), `/Library/Application Support/ClaudeCode/...` (macOS) | All users in org | 1 (highest) |
| Personal | `~/.claude/skills/<skill-name>/SKILL.md` | All your projects | 2 |
| Project | `.claude/skills/<skill-name>/SKILL.md` | This project only | 3 |
| Plugin | `<plugin>/skills/<skill-name>/SKILL.md` | Where plugin enabled | Uses namespace: `plugin-name:skill-name` |

**Automatic discovery from nested directories:**

When editing files in subdirectories (e.g., `packages/frontend/src/Button.tsx`), Claude automatically discovers skills from:
- `.claude/skills/` at project root
- `packages/frontend/.claude/skills/` (nested, at depth of file)
- All parent directories up the tree

This enables monorepo setups where subprojects have their own skills.

---

## 2. How Slash Commands Are Registered & Discovered

### Slash Command Discovery

The `name` field in SKILL.md frontmatter becomes the slash command. A skill named `deploy` becomes `/deploy`.

**Invocation methods:**

1. **Automatic (if `disable-model-invocation: false`):** Claude loads skill description at startup, triggers it automatically when relevant to conversation
2. **Manual (user invokes):** Type `/skill-name` to invoke directly
3. **Programmatic (Claude):** Claude can invoke skills directly using the Skill tool

### Custom Commands vs Skills

**Custom commands** (legacy, still supported):
- Files at `.claude/commands/review.md`
- Create a `/review` slash command
- No supporting files, limited features

**Skills** (recommended):
- Directory-based at `.claude/skills/review/SKILL.md`
- Create a `/review` slash command
- Support supporting files (reference docs, templates, scripts)
- Support invocation control (`disable-model-invocation`, `user-invocable`)
- Support subagent execution (`context: fork`)
- Support pre-loading for subagents

**Transition:** Custom commands are deprecated but still work. If a skill and command share the same name, **the skill takes precedence**. Recommend migrating to skills for new features.

### Slash Command Resolution Order

When you type `/skill-name`:
1. Check project `.claude/skills/skill-name/SKILL.md` (highest priority)
2. Check personal `~/.claude/skills/skill-name/SKILL.md`
3. Check enterprise location (if configured)
4. Check `.claude/commands/skill-name.md` (legacy, lowest priority)
5. Return "command not found"

---

## 3. Best Practices for Skill Design

### Parameterization Strategy

Skills support argument passing via string substitution:

**Variable substitutions available:**

| Variable | Meaning | Example |
|----------|---------|---------|
| `$ARGUMENTS` | All arguments as single string | `/fix-issue Update login flow` → "Update login flow" |
| `$ARGUMENTS[N]` or `$N` | Specific argument by index (0-based) | `/migrate-component Button React Vue` → `$0`="Button", `$1`="React", `$2`="Vue" |
| `${CLAUDE_SESSION_ID}` | Current session ID | Useful for logging or creating session-specific files |

**Pattern: Optional arguments auto-append**

If you use `$ARGUMENTS` in content, it replaces the placeholder. If you don't use it, Claude Code automatically appends `ARGUMENTS: <user-input>` to the end of the skill, so Claude still sees what was passed.

**Example parameterized skill:**

```yaml
---
name: fix-issue
description: Fix a GitHub issue by number
disable-model-invocation: true
argument-hint: [issue-number]
---

Fix GitHub issue $ARGUMENTS following our coding standards.

1. Read the issue description
2. Understand requirements
3. Implement the fix
4. Write tests
5. Commit with descriptive message
```

Invoke with: `/fix-issue 123`
Claude receives: "Fix GitHub issue 123 following..."

### Context Injection Best Practices

#### Dynamic Context Injection (Preprocessing)

Use the `!` command syntax to run shell commands before the skill content is sent to Claude:

```yaml
---
name: pr-summary
description: Summarize a pull request
---

## PR Context

- **Diff**: !`gh pr diff`
- **Comments**: !`gh pr view --comments`
- **Files changed**: !`gh pr diff --name-only`

## Task

Summarize the above pull request changes...
```

**How it works:**

1. Each `!` command executes immediately (before Claude sees anything)
2. Output replaces the placeholder
3. Claude receives fully-rendered prompt with actual data

This is preprocessing, not runtime execution. Claude only sees the final result.

#### Path-Based Rules (via .claude/rules/)

For per-file-type guidance, use `.claude/rules/` with path-specific frontmatter:

```markdown
---
paths:
  - "src/api/**/*.ts"
  - "**/*.test.ts"
---

# API Testing Rules

- All endpoints require input validation tests
- Use standard error response format in tests
- Include OpenAPI documentation comments
```

**Rules vs Skills:**

| Mechanism | Load timing | Scope | Use case |
|-----------|-------------|-------|----------|
| `.claude/rules/` | At session start (unconditional) or on file match (conditional) | Specific files via glob patterns | Guidance for entire file types (all API files, all tests) |
| Skills | On-demand when relevant/invoked | All files in scope | Domain-specific workflows to invoke explicitly |

### Size & Performance Guidelines

**SKILL.md body size:**
- **Target:** Under 500 lines
- **Maximum practical:** 1000 lines (with degradation)
- **Recommendation:** Use progressive disclosure — keep SKILL.md focused, split detailed content into separate files

**Supporting file strategy:**

Good architecture:
```
skill/
├── SKILL.md (100-200 lines, navigation + essentials)
├── reference.md (detailed API docs, loaded on-demand)
├── examples.md (usage examples, loaded on-demand)
└── scripts/
    └── validate.py (executed, not loaded)
```

Bad architecture:
```
skill/
└── SKILL.md (1500 lines, everything inline)
```

**Why:** Context fills up fast. Claude loads reference.md or examples.md only when needed. A 1500-line SKILL.md is always loaded, consuming context on every invocation.

### Naming Conventions

**Recommended:** Use gerund form (verb + -ing) for clarity:
- ✅ `processing-pdfs` (clearly describes action)
- ✅ `analyzing-spreadsheets`
- ✅ `managing-databases`

**Acceptable alternatives:**
- Noun phrases: `pdf-processing`
- Action-oriented: `process-pdfs`

**Avoid:**
- Vague: `helper`, `utils`, `tools`
- Generic: `documents`, `data`, `files`
- Reserved words: `anthropic-*`, `claude-*`

Use consistent patterns within your skill collection.

### Invocation Control Strategy

Control when and how skills can be invoked:

**`disable-model-invocation: true` — manual only**

Use for workflows with side effects you want to control timing on:

```yaml
---
name: deploy
description: Deploy the application to production
disable-model-invocation: true
---

Deploy to production:

1. Run test suite
2. Build application
3. Push to deployment target
4. Verify deployment succeeded
```

Claude won't trigger this automatically, only when you type `/deploy`.

**`user-invocable: false` — Claude only**

Use for background knowledge that isn't actionable as a command:

```yaml
---
name: legacy-system-context
description: How the legacy authentication system works (for context only)
user-invocable: false
---

# Legacy Auth System

[Detailed explanation of old system]
```

Claude loads this when relevant, but `/legacy-system-context` won't appear in the `/` menu.

**Default (both fields omitted or false):**

Skill can be invoked by you (`/skill-name`) and by Claude automatically when relevant.

---

## 4. How .claude/rules/ Conditional Context Injection Works

### Purpose & Scope

`.claude/rules/` provides **path-specific, auto-activating context injection**. Rules are markdown files that Claude reads at session start (or when matching files are opened).

**Key difference from skills:**

| Rules | Skills |
|-------|--------|
| Auto-load (unconditional) at session start OR on file match (conditional) | Load only when invoked or Claude deems relevant |
| All files in `.claude/rules/` are discovered | Must invoke `/skill-name` or Claude decides |
| Can be scoped to file paths | Apply globally to all files in scope |
| Always contextual guidance | Can be workflows or domain knowledge |

### File Structure & Format

```
your-project/
├── .claude/
│   ├── CLAUDE.md           # Main project instructions
│   └── rules/
│       ├── api-design.md   # Unconditional rule
│       ├── testing.md      # Unconditional rule
│       ├── security.md     # Unconditional rule
│       └── api/
│           └── handlers.md # Can organize in subdirs
```

**Rule file format (optional YAML frontmatter):**

```markdown
---
paths:
  - "src/api/**/*.ts"
  - "src/**/*.test.ts"
---

# API Development Rules

- All endpoints must include input validation
- Use standard error response format
- Include OpenAPI documentation comments
```

**Rules without `paths` frontmatter:** Load unconditionally at session start (like CLAUDE.md)

**Rules with `paths` frontmatter:** Load when Claude opens/reads files matching the patterns

### Path Patterns & Globbing

Rules use glob patterns to match files:

| Pattern | Matches |
|---------|---------|
| `**/*.ts` | All TypeScript files in any directory |
| `src/**/*` | All files under `src/` |
| `*.md` | Markdown files in project root |
| `src/components/*.tsx` | React components in specific directory |
| `src/**/*.{ts,tsx}` | Brace expansion: TS or TSX files |
| `**/*.test.*` | All test files (any extension) |

**Multiple patterns:**

```yaml
---
paths:
  - "src/api/**/*.ts"
  - "tests/**/*.test.ts"
  - "**/*.spec.ts"
---
```

### Load Priority & Precedence

Rules load in this order (later overrides earlier):

1. User-level rules (`~/.claude/rules/`)
2. Project root rules (`.claude/rules/`)
3. Ancestor directory rules (in parent projects)
4. CLAUDE.md files (same precedence as rules)

Path-scoped rules trigger when files match. Unconditional rules always load.

### Symlink Support

`.claude/rules/` supports symlinks for sharing rules across projects:

```bash
# Link shared rules directory
ln -s ~/shared-claude-rules .claude/rules/shared

# Link specific rule file
ln -s ~/company-standards/security.md .claude/rules/security.md
```

Symlinks are resolved and loaded normally. Circular symlinks are detected and skipped.

### Organization Patterns

**By file type:**

```
.claude/rules/
├── frontend.md    # Rules for React/Vue/UI code
├── backend.md     # Rules for API/server code
├── testing.md     # Rules for test files
└── security.md    # Rules for auth/sensitive code
```

**By domain (monorepo):**

```
.claude/rules/
├── api/
│   ├── handlers.md
│   ├── validation.md
│   └── errors.md
└── frontend/
    ├── components.md
    ├── hooks.md
    └── styling.md
```

**Conditional (path-scoped):**

```
.claude/rules/
├── unconditional.md        # Always loaded
├── api-rules.md
│   paths: ["src/api/**"]   # Only for API code
└── test-rules.md
    paths: ["**/*.test.*"]  # Only for test files
```

---

## 5. Limitations of Skills

### Context Budget Constraints

**Skill descriptions budget:**

- **Mechanism:** All skill descriptions (name + description fields) are loaded into context at startup
- **Budget size:** 2% of context window (dynamic), with 16,000 character fallback minimum
- **Overflow:** If descriptions exceed budget, Claude warns "some skills excluded" (visible via `/context`)
- **Override:** Set `SLASH_COMMAND_TOOL_CHAR_BUDGET` environment variable to increase

**Impact:** With many skills (50+), description tokens can be significant. Well-written descriptions (concise, specific) reduce overflow risk.

### SKILL.md Body Size Limits

**Performance degradation:**

- **Recommended max:** 500 lines per SKILL.md body
- **Hard limit:** No technical hard limit, but performance degrades significantly above 1000 lines
- **Solution:** Use progressive disclosure — split content into separate reference files

**Why this matters:** Once Claude loads SKILL.md, every line competes with conversation history. A 1500-line SKILL.md consumes ~4000 tokens per invocation.

### Nested File Reference Limitations

**Risk of incomplete reads:**

When Claude encounters deeply nested file references, it may use `head -100` or similar truncation rather than reading entire files. This causes incomplete information.

**Bad nesting example:**

```
SKILL.md → advanced.md → details.md → actual_info.md
```

Claude may only read first 100 lines of details.md, missing critical information in actual_info.md.

**Solution: Keep references one level deep:**

```
SKILL.md →┬→ reference.md
          ├→ examples.md
          └→ advanced.md
```

All reference files link directly from SKILL.md, ensuring complete file reads.

### No Transitive Parameterization

Skills don't support passing parameters through skill-to-skill invocation. If `/skill-a` invokes `/skill-b`, the arguments don't automatically flow through.

**Workaround:** Design skills for independence. If you need composition, use subagents with preloaded skills instead.

### Limited Nesting & Chaining

**Claude doesn't automatically chain skills.** If you want skill A to invoke skill B as part of its workflow:

1. **Not recommended:** Embed `/skill-b` invocation in SKILL.md content — Claude may not execute it
2. **Better:** Use `context: fork` with subagent execution, where you control the environment
3. **Best:** Design skills as independent units, not dependent chains

### Subagent Context Limitation

When running a skill with `context: fork`:

- Skill content becomes the task prompt
- Subagent gets isolated context (no conversation history)
- CLAUDE.md is loaded, but `.claude/rules/` rules are NOT automatically inherited
- You must explicitly mention which rules apply

**Implication:** Subagent-executed skills need self-contained instructions. Can't rely on context from main session.

### Tool Permission Constraints

**`allowed-tools` field restrictions:**

- Limits which tools Claude can use when the skill is active
- Still respects baseline permission rules from `/permissions`
- Doesn't grant access to tools you've denied globally — only enables allowed-by-default tools
- Scripts can only use tools you specify

**Example:** A read-only skill with `allowed-tools: Read, Grep, Glob` cannot write files, even if the file system allows it elsewhere.

---

## 6. Skill Chaining & Composition Patterns

### Composition Strategy

**Direct composition (not recommended):**

```yaml
---
name: workflow
description: Complex workflow
---

Run /step-1
Then run /step-2
Then run /step-3
```

**Problem:** Claude may not execute nested slash commands reliably.

**Recommended approach: Subagent orchestration**

```yaml
---
name: workflow
description: Complex workflow
context: fork
agent: general-purpose
---

You have access to these skills: step-1, step-2, step-3

Execute them in sequence:
1. Use /step-1 to...
2. Use /step-2 to...
3. Use /step-3 to...

Report results.
```

Skills preloaded into subagent execute more reliably than explicit calls.

### Progressive Skill Disclosure

For multi-step workflows, use progressive disclosure:

```yaml
---
name: orchestrator
description: Orchestrates complex workflow
---

# Workflow Overview

This skill guides you through a 3-step process.
See [STEP-1.md](STEP-1.md), [STEP-2.md](STEP-2.md), [STEP-3.md](STEP-3.md) for details.

## Step 1: Analyze
Read [STEP-1.md](STEP-1.md) and follow the instructions...

## Step 2: Plan
Read [STEP-2.md](STEP-2.md) and follow the instructions...

## Step 3: Implement
Read [STEP-3.md](STEP-3.md) and follow the instructions...
```

Each file is loaded on-demand, keeping the main skill focused.

---

## 7. Key Findings for gsd-multi-model Project

### For `/init-gsd` Skill

The `init-gsd` skill in this project bootstraps new projects with GSD + Claude Code integration. Based on research:

**Strengths:**
- ✅ Correctly structured as directory-based skill with metadata
- ✅ Uses `disable-model-invocation: true` appropriately (manual initialization only)
- ✅ Clearly scoped (`allowed-tools` limits to safe operations)
- ✅ References supporting files (Codex config, rules templates)

**Recommendations:**
1. **Keep SKILL.md under 500 lines:** Current version is ~236 lines (good). If grows, split step instructions into separate files.
2. **Be explicit about symlink rules location:** Rules templates reference `.claude/rules/` creation, but could clarify that these apply at project level only.
3. **Consider argument substitution:** Could use `$ARGUMENTS` for custom project naming beyond directory name.
4. **Document context: fork option:** Skill doesn't use `context: fork`, but could benefit from isolated execution in large monorepos.

### For Dual-Tool Skill Architecture

The `/codex-review` and `/gsd-codex-verify` skills implement cross-model validation:

**Strengths:**
- ✅ Correctly use `disable-model-invocation: true` (user-triggered review only)
- ✅ Both delegate to external processes (Codex CLI) rather than trying to compose complex logic
- ✅ Structured as workflow guides, not prescriptive code

**Opportunity:**
- Consider whether `/gsd-codex-verify` could be split into two subagent-delegated skills (one for GSD verification, one for cross-review) to provide more granular verification gates

### For Rules-Based Context

Projects using gsd-multi-model should leverage `.claude/rules/` for:

```
.claude/rules/
├── gsd-workflow.md           # Always active
├── planning-files.md         # Activates on .planning/**
├── test-files.md             # Activates on test/**
└── security.md               # Activates on sensitive files
```

This ensures GSD workflow guidance stays fresh without consuming main conversation context.

---

## Confidence Assessment

| Area | Level | Evidence |
|------|-------|----------|
| Skill file structure & metadata | HIGH | Official Claude Code docs + multiple example skills in codebase |
| SKILL.md format & frontmatter | HIGH | Comprehensive official documentation + tested examples |
| Slash command registration | HIGH | Clear in official docs + working examples (`/init-gsd`, `/codex-review`) |
| Progressive disclosure mechanism | HIGH | Documented with detailed examples + observed in practice |
| .claude/rules conditional injection | HIGH | Official docs + detailed path-based examples |
| Context budgets & limitations | MEDIUM | Official docs mention 2% budget + 16KB fallback, but exact token costs vary by model |
| Skill chaining best practices | MEDIUM | Documented patterns, but some anti-patterns inferred from official guidance |
| Performance at scale (50+ skills) | MEDIUM | Budget mentioned, but limited real-world data on performance degradation |

---

## Open Questions & Gaps

1. **Exact context cost per skill description:** Docs state "2% of context window" but actual token cost depends on model (Haiku vs Opus). Consider empirical testing.

2. **Behavior when skill descriptions exceed budget:** Docs say Claude warns, but unclear if skills are randomly excluded or by priority. May warrant testing with large skill collections.

3. **Nested .claude/skills discovery depth:** Docs mention nested discovery but don't specify max depth. Are skills discovered 3+ levels deep, or only immediate subdirectories?

4. **Subagent skill inheritance:** When `context: fork` runs, which `.claude/rules/` rules load? Do path-scoped rules apply in the subagent context?

5. **Performance degradation curve:** At what SKILL.md size does performance noticeably degrade (500 lines, 1000, 2000)?

---

## Key Recommendations for gsd-multi-model

1. **Keep skills focused & small:** Maintain SKILL.md bodies under 300 lines. Use separate reference files for detailed content.

2. **Document skill discovery:** In project README, explain where skills are installed (`~/.claude/skills/` vs `.claude/skills/`) and how nested discovery works.

3. **Version the skill format:** If skills are distributed, include a `format_version` or `min_claude_version` field in frontmatter for compatibility.

4. **Use rules for workflow guidance:** Move repetitive workflow instructions from CLAUDE.md into `.claude/rules/` to keep main context clean.

5. **Test skill descriptions:** Ensure descriptions are specific enough to trigger auto-discovery. Vague descriptions (e.g., "helper tool") won't match user requests reliably.

6. **Implement skill updates gracefully:** If updating installed skills, ensure backward compatibility (old skills still work with new features).

---

## Sources

- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [Claude Code Memory & Rules](https://code.claude.com/docs/en/memory)
- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices)
- [Claude API Skill Authoring Best Practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [Inside Claude Code Skills: Structure, Prompts, Invocation](https://mikhail.io/2025/10/claude-code-skills/)
- [Claude Code Gets Path-Specific Rules](https://paddo.dev/blog/claude-rules-path-specific-native/)
- [Claude Code Merges Slash Commands Into Skills](https://medium.com/@joe.njenga/claude-code-merges-slash-commands-into-skills-dont-miss-your-update-8296f3989697)
