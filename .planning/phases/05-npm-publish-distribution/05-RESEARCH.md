# Phase 05: NPM Publish & Distribution - Research

**Researched:** 2026-03-11
**Domain:** npm packaging, shell-based CLI distribution, version compatibility
**Confidence:** HIGH

## Summary

This phase packages the existing gsd-multi-model project for npm distribution. The project is already 90% ready: `package.json` has correct `bin`, `files`, and metadata; `bin/cli.sh` (281 lines) handles all installation logic; `gsd-compat.json` defines version compatibility. The remaining work is: (1) update `gsd-compat.json` addon_version to match package.json, (2) wire version compat checking into cli.sh using gsd-compat.json, (3) add anti-duplication guards, (4) verify the npm publish flow works, and (5) update repository URL.

**Primary recommendation:** This is a polish-and-publish phase, not a build-from-scratch phase. The CLI and package structure exist. Focus on hardening the version check, ensuring clean `npm pack` output, and documenting the publish workflow.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None -- all decisions deferred to Claude's discretion.

### Claude's Discretion
All implementation decisions deferred to Claude's judgment.
/gsd:drive auto-generated this context -- no user discussion occurred.
Research and planning agents should make reasonable default choices.

### Deferred Ideas (OUT OF SCOPE)
None
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DIST-01 | `npx gsd-multi-model` installs skills (default), `--all` for full setup | cli.sh already implements this -- verify npx execution path works |
| DIST-02 | Package published to npm with correct `bin`, `files`, and metadata | package.json exists with bin/files/keywords -- needs repo URL fix, version bump, publish verification |
| DIST-03 | Version compatibility check against base GSD on install | gsd-compat.json exists with min/max/tested -- cli.sh needs to read and enforce it with semver comparison |
| DIST-04 | Clean separation -- GSD base is prerequisite, multi-model is add-on only | cli.sh already warns if GSD not found -- add explicit anti-duplication checks |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| npm | 10.x | Package registry and distribution | Only viable public JS package registry |
| bash | 4+ | CLI entry point (bin/cli.sh) | Already built, 281 lines, works |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `npm pack` | Verify package contents before publish | Pre-publish validation |
| `npm publish --dry-run` | Simulate publish without uploading | Final check before real publish |
| `semver` (bash) | Version comparison in cli.sh | DIST-03 compat checking |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bash semver | Node.js semver package | Adds runtime dependency for a CLI that's pure bash -- not worth it |
| npm publish | GitHub Packages | npm is more accessible, GSD base is already on npm |

## Architecture Patterns

### Current Package Structure (already exists)
```
gsd-multi-model/
  bin/cli.sh          # Entry point (package.json bin)
  skills/             # 9 skill directories
  global/             # Codex config templates
  rules/              # Claude rules templates
  gsd-compat.json     # Version compatibility matrix
  package.json        # npm metadata
```

### Pattern 1: Shell bin via npm
**What:** npm's `bin` field points to a shell script, npm adds it to PATH on install
**When to use:** When the CLI is bash-native (no Node.js needed)
**Key detail:** The shebang `#!/usr/bin/env bash` is required. npm will create a symlink on `npm install -g` or execute directly via `npx`.

### Pattern 2: Semver Comparison in Bash
**What:** Compare version strings without external dependencies
**Implementation:**
```bash
# Split version into components and compare numerically
version_gte() {
  local IFS=.
  local i ver1=($1) ver2=($2)
  for ((i=0; i<${#ver2[@]}; i++)); do
    if ((${ver1[i]:-0} < ${ver2[i]:-0})); then return 1; fi
    if ((${ver1[i]:-0} > ${ver2[i]:-0})); then return 0; fi
  done
  return 0
}
```

### Pattern 3: Anti-Duplication Guard
**What:** Detect if installing would overwrite GSD base files
**Implementation:** Check that skills being installed are multi-model-specific, not GSD base skills. The cli.sh loop over `skills/*/` already only installs what's in this package's skills dir.

### Anti-Patterns to Avoid
- **postinstall scripts:** Do NOT use npm postinstall to auto-run cli.sh. Users expect `npx gsd-multi-model` to be explicit, not side-effect-driven.
- **Node.js wrapper around bash:** Do NOT create an index.js that shells out to cli.sh. The bin field directly pointing to cli.sh works fine.
- **Bundling GSD base:** NEVER include GSD base files in this package. It's an add-on only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Package publishing | Custom upload scripts | `npm publish` | Standard, handles auth/registry/versioning |
| Package validation | Manual file checks | `npm pack --dry-run` | Shows exactly what gets published |
| Version management | Manual edits | `npm version patch/minor/major` | Updates package.json + creates git tag |

## Common Pitfalls

### Pitfall 1: Missing files in npm package
**What goes wrong:** Published package doesn't include skills/ or other directories
**Why it happens:** npm uses `files` array as allowlist; forgetting an entry excludes it
**How to avoid:** Run `npm pack --dry-run` and verify all expected files appear
**Warning signs:** `npx gsd-multi-model` runs but installs zero skills

### Pitfall 2: Shell script not executable
**What goes wrong:** `npx gsd-multi-model` fails with permission denied
**Why it happens:** Git doesn't always preserve execute bit; npm needs it for bin scripts
**How to avoid:** Ensure `chmod +x bin/cli.sh` and commit with execute permission. Verify with `git ls-files -s bin/cli.sh` (should show 100755)
**Warning signs:** Works locally but fails after npm install

### Pitfall 3: SCRIPT_DIR resolution in npx context
**What goes wrong:** cli.sh can't find skills/ directory when run via npx
**Why it happens:** npx runs from a temp directory or node_modules/.bin; `SCRIPT_DIR` must resolve to the package root, not the symlink location
**How to avoid:** Current code uses `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)` which follows symlinks correctly via BASH_SOURCE. Verify this works in npx context.
**Warning signs:** "No such file or directory" errors for skills paths

### Pitfall 4: gsd-compat.json addon_version drift
**What goes wrong:** gsd-compat.json says addon_version 1.2.0 but package.json says 1.3.0
**Why it happens:** Manual version management across two files
**How to avoid:** Either update both in the same commit, or have cli.sh read version from package.json instead of gsd-compat.json

### Pitfall 5: Repository URL placeholder
**What goes wrong:** package.json has `your-org/gsd-multi-model` placeholder
**How to avoid:** Update to actual GitHub URL before publishing

## Code Examples

### Verify package contents before publish
```bash
npm pack --dry-run 2>&1
# Should list: bin/cli.sh, skills/**, global/**, rules/**, gsd-compat.json, package.json
```

### Version compat check (to add to cli.sh)
```bash
COMPAT_FILE="$SCRIPT_DIR/gsd-compat.json"
if [ -f "$COMPAT_FILE" ] && [ -f "$VERSION_FILE" ]; then
  MIN_VER=$(grep -o '"min": *"[^"]*"' "$COMPAT_FILE" | cut -d'"' -f4)
  MAX_VER=$(grep -o '"max": *"[^"]*"' "$COMPAT_FILE" | cut -d'"' -f4)
  if ! version_gte "$GSD_VERSION" "$MIN_VER"; then
    warn "GSD v${GSD_VERSION} is below minimum v${MIN_VER}"
  fi
  if ! version_gte "$MAX_VER" "$GSD_VERSION"; then
    warn "GSD v${GSD_VERSION} is above tested range (max v${MAX_VER})"
  fi
fi
```

### Publish workflow
```bash
# 1. Verify contents
npm pack --dry-run

# 2. Bump version
npm version minor  # or patch/major

# 3. Update gsd-compat.json addon_version to match

# 4. Publish
npm publish

# 5. Verify
npx gsd-multi-model --help
```

## State of the Art

| What | Current State | Impact |
|------|---------------|--------|
| package.json | Exists, mostly correct | Needs repo URL, version sync |
| bin/cli.sh | Complete, 281 lines | No changes needed for DIST-01 |
| gsd-compat.json | Exists, addon_version stale (1.2.0 vs 1.3.0) | Needs sync + enforcement in cli.sh |
| Version compat check | cli.sh checks GSD exists but not version range | Need semver comparison using gsd-compat.json |
| Anti-duplication | cli.sh only copies its own skills/ | Already safe, document explicitly |
| npm auth | Not logged in on this machine | Need `npm login` before publish |

## Open Questions

1. **npm scope**
   - What we know: Package name is `gsd-multi-model` (unscoped)
   - What's unclear: Should it be `@gsd/multi-model` or stay unscoped?
   - Recommendation: Keep unscoped -- matches `get-shit-done-cc` pattern, simpler for npx

2. **Repository URL**
   - What we know: Currently placeholder `your-org/gsd-multi-model`
   - What's unclear: Actual GitHub org/repo
   - Recommendation: User must provide before publish; can proceed with placeholder for now

3. **npm auth**
   - What we know: Not logged in on this machine
   - Recommendation: `npm login` is a manual step, document in publish checklist

## Sources

### Primary (HIGH confidence)
- Existing codebase: package.json, bin/cli.sh, gsd-compat.json -- direct inspection
- npm documentation on `bin` field, `files` field, `npx` execution model

### Secondary (MEDIUM confidence)
- BASH_SOURCE symlink resolution behavior for npx context

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - npm publish is well-understood, package.json already exists
- Architecture: HIGH - cli.sh is already built and working
- Pitfalls: HIGH - identified from direct code inspection of existing cli.sh

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable domain, npm packaging rarely changes)
