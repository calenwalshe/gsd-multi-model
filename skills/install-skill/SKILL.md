---
name: install-skill
description: Install Claude Code skills from a GitHub URL. Clones the repo, finds all SKILL.md files, and installs them to ~/.claude/skills/.
argument-hint: <github-url> [--force]
allowed-tools: Bash, Read, Glob, Write
---

# Install Skill from GitHub

Install Claude Code skills from any GitHub repository.

## Usage

```
/install-skill https://github.com/user/repo
/install-skill https://github.com/user/repo --force    # overwrite existing
```

## Process

1. **Parse arguments:**
   - Extract URL from `$ARGUMENTS` (first argument that looks like a URL)
   - Check for `--force` flag
   - If no URL provided, error: `Usage: /install-skill <github-url> [--force]`

2. **Clone to temp directory:**
   ```bash
   TMPDIR=$(mktemp -d /tmp/install-skill-XXXX)
   git clone --depth 1 "$URL" "$TMPDIR/repo" 2>&1
   ```
   - If clone fails, report error and clean up

3. **Discover skills:**
   ```bash
   find "$TMPDIR/repo" -name "SKILL.md" -type f
   ```
   - For each SKILL.md found, extract the parent directory name as the skill name
   - Read each SKILL.md frontmatter to get the `name` and `description` fields
   - Present what was found:
     ```
     Found N skill(s) in repo:

     | Skill | Description |
     |-------|-------------|
     | init-gsd | Bootstrap a project with GSD workflow |
     | codex-review | Cross-model review via Codex |
     ```

4. **Check for conflicts:**
   - For each skill, check if `~/.claude/skills/{name}/` already exists
   - If exists and no `--force`: warn and skip
   - If exists and `--force`: overwrite

5. **Install skills:**
   ```bash
   cp -r "$SKILL_DIR" "$HOME/.claude/skills/"
   ```
   - Report each install: `Installed: {name} → ~/.claude/skills/{name}/`

6. **Check for install.sh:**
   - If the repo has an `install.sh` at root, offer to run it:
     ```
     This repo also has an install.sh. Run it for additional setup? (configs, rules, etc.)
     ```
   - Only run if user approves

7. **Clean up:**
   ```bash
   rm -rf "$TMPDIR"
   ```

8. **Report:**
   ```
   Installed N skill(s) from {repo-name}:
   - /skill-name-1
   - /skill-name-2

   Skills are available immediately in all projects.
   ```

## Error Handling

- No URL → show usage
- Clone fails → "Could not clone {URL}. Check the URL and your GitHub access."
- No SKILL.md found → "No skills found in this repository."
- Permission error → "Cannot write to ~/.claude/skills/. Check permissions."
