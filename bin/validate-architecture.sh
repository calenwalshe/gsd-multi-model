#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# validate-architecture.sh -- Architecture constraint validator
#
# Validates files against .architecture.json module boundary rules.
# Checks import/source statements for violations of cannot_import
# and cannot_reach constraints.
#
# Usage:
#   bin/validate-architecture.sh .architecture.json [file1 file2 ...]
#
# Output:
#   stdout: JSON {"passed": bool, "files_checked": N, "violations": [...]}
#   exit 0: no violations
#   exit 1: violations found or config error
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Validate arguments ---
if [ $# -lt 1 ]; then
  echo '{"passed":false,"files_checked":0,"violations":[{"file":"","rule":"config","message":"Usage: validate-architecture.sh <config-path> [files...]","fix":"Provide architecture config path as first argument"}]}'
  exit 1
fi

ARCH_CONFIG="$1"
shift

# Resolve config path
if [[ "$ARCH_CONFIG" != /* ]]; then
  ARCH_CONFIG="$PROJECT_ROOT/$ARCH_CONFIG"
fi

if [ ! -f "$ARCH_CONFIG" ]; then
  echo '{"passed":false,"files_checked":0,"violations":[{"file":"'"$ARCH_CONFIG"'","rule":"config","message":"Architecture config file not found","fix":"Create .architecture.json in project root"}]}'
  exit 1
fi

# Validate JSON
if ! node -e "JSON.parse(require('fs').readFileSync('$ARCH_CONFIG','utf8'))" 2>/dev/null; then
  echo '{"passed":false,"files_checked":0,"violations":[{"file":"'"$ARCH_CONFIG"'","rule":"config","message":"Architecture config is not valid JSON","fix":"Fix JSON syntax in .architecture.json"}]}'
  exit 1
fi

# If no files provided, pass
if [ $# -eq 0 ]; then
  echo '{"passed":true,"files_checked":0,"violations":[]}'
  exit 0
fi

# --- Run validation via Node (reliable glob matching + JSON handling) ---
FILES_JSON="["
first=true
for f in "$@"; do
  if [ "$first" = true ]; then
    first=false
  else
    FILES_JSON="$FILES_JSON,"
  fi
  FILES_JSON="$FILES_JSON\"$f\""
done
FILES_JSON="$FILES_JSON]"

node -e "
const fs = require('fs');
const path = require('path');

const config = JSON.parse(fs.readFileSync('$ARCH_CONFIG', 'utf8'));
const files = $FILES_JSON;
const projectRoot = '$PROJECT_ROOT';
const violations = [];
let filesChecked = 0;

// Simple glob matcher: supports * and **
function globMatch(pattern, filepath) {
  // Normalize: remove trailing slashes for comparison
  const pat = pattern.replace(/\/+\$/, '');
  const fp = filepath.replace(/\/+\$/, '');

  // Convert glob to regex
  let regex = pat
    .replace(/[.+^\\\\{}()|[\]]/g, '\\\\\\$&')  // escape special regex chars
    .replace(/\*\*/g, '__DOUBLESTAR__')
    .replace(/\*/g, '[^/]*')
    .replace(/__DOUBLESTAR__/g, '.*');

  return new RegExp('^' + regex).test(fp);
}

// Find which module a file belongs to
function findModule(filepath) {
  for (const [pattern, mod] of Object.entries(config.modules || {})) {
    if (globMatch(pattern, filepath)) {
      return { pattern, mod };
    }
  }
  return null;
}

// Extract imports from a file based on extension
function extractImports(filepath, content) {
  const ext = path.extname(filepath);
  const imports = [];

  if (ext === '.md') {
    // Skip Markdown files -- references are documentation, not runtime deps
    return imports;
  }

  if (ext === '.sh' || ext === '.bash' || ext === '') {
    // Check shebang for shell scripts without extension
    const isShell = ext === '.sh' || ext === '.bash' || content.startsWith('#!/');
    if (isShell) {
      // Match: source path, . path (dot-source)
      const sourceRegex = /^\\s*(?:source|\\.)\\s+[\"']?([^\"'\\s#]+)[\"']?/gm;
      let m;
      while ((m = sourceRegex.exec(content)) !== null) {
        imports.push(m[1]);
      }
    }
  }

  if (['.js', '.ts', '.cjs', '.mjs', '.jsx', '.tsx'].includes(ext)) {
    // require('path') and require(\"path\")
    const requireRegex = /require\\s*\\(\\s*['\"]([^'\"]+)['\"]\\s*\\)/g;
    let m;
    while ((m = requireRegex.exec(content)) !== null) {
      imports.push(m[1]);
    }
    // import ... from 'path'
    const importRegex = /import\\s+.*?from\\s+['\"]([^'\"]+)['\"]/g;
    while ((m = importRegex.exec(content)) !== null) {
      imports.push(m[1]);
    }
    // import 'path' (side-effect import)
    const sideImportRegex = /^import\\s+['\"]([^'\"]+)['\"]/gm;
    while ((m = sideImportRegex.exec(content)) !== null) {
      imports.push(m[1]);
    }
  }

  return imports;
}

// Resolve an import path relative to the importing file
function resolveImport(importPath, fromFile) {
  // Skip node_modules / built-in imports
  if (!importPath.startsWith('.') && !importPath.startsWith('/') && !importPath.startsWith('\$')) {
    // Could be a project-root-relative path like 'bin/something'
    // Check if it looks like a project path
    const possiblePath = importPath.replace(/^[\"']|[\"']\$/g, '');
    if (possiblePath.match(/^(bin|skills|global|src)\//)) {
      return possiblePath;
    }
    return null; // external module
  }

  // Handle variable paths like \$SCRIPT_DIR/...
  if (importPath.includes('\$')) {
    // Try to resolve common patterns
    const cleaned = importPath
      .replace(/\\\$SCRIPT_DIR/g, path.dirname(fromFile))
      .replace(/\\\$HOME\\/\\.claude\\/get-shit-done/g, '__GSD__');
    if (cleaned.includes('__GSD__')) return null; // GSD framework import, not project
    return path.normalize(cleaned);
  }

  // Relative path
  const dir = path.dirname(fromFile);
  return path.normalize(path.join(dir, importPath));
}

// Check files
for (const file of files) {
  const fullPath = path.isAbsolute(file) ? file : path.join(projectRoot, file);

  // Skip if file doesn't exist (might be deleted)
  if (!fs.existsSync(fullPath)) continue;

  // Skip Markdown files entirely (per research pitfall 3)
  if (file.endsWith('.md')) continue;

  const module = findModule(file);
  if (!module) continue; // File not in any module -- skip

  filesChecked++;
  const content = fs.readFileSync(fullPath, 'utf8');
  const imports = extractImports(file, content);

  for (const imp of imports) {
    const resolved = resolveImport(imp, file);
    if (!resolved) continue;

    // Check cannot_import rules
    const cannotImport = module.mod.cannot_import || [];
    for (const forbidden of cannotImport) {
      if (globMatch(forbidden, resolved)) {
        violations.push({
          file: file,
          rule: 'cannot_import',
          message: module.pattern + ' cannot import from ' + forbidden + ' (found: ' + imp + ')',
          fix: 'Move shared logic to an allowed module or restructure the dependency'
        });
      }
    }

    // Check global rules
    for (const rule of (config.rules || [])) {
      if (globMatch(rule.from, file) && globMatch(rule.cannot_reach, resolved)) {
        violations.push({
          file: file,
          rule: rule.name,
          message: rule.description + ' (found: ' + imp + ' -> ' + resolved + ')',
          fix: 'Move shared logic to bin/ or a shared utility'
        });
      }
    }
  }
}

const result = {
  passed: violations.length === 0,
  files_checked: filesChecked,
  violations: violations
};

console.log(JSON.stringify(result, null, 2));
process.exit(violations.length > 0 ? 1 : 0);
" 2>/dev/null
