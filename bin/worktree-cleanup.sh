#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# gsd worktree-cleanup -- Merge and remove a GSD worktree
#
# Merges the worktree branch back into the current branch,
# removes the worktree directory, and deletes the branch.
#
# Usage:
#   bin/worktree-cleanup.sh <branch>                    # merge and remove
#   bin/worktree-cleanup.sh <branch> --json             # machine-readable output
#   bin/worktree-cleanup.sh --no-merge --force <branch> # discard without merging
#   bin/worktree-cleanup.sh --all                       # merge all GSD worktrees
#   bin/worktree-cleanup.sh --all --no-merge --force    # discard all
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- ANSI color helpers with TTY detection ---
if [ -t 2 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BOLD=''
  RESET=''
fi

ok()   { echo -e "${GREEN}  ok${RESET} $1" >&2; }
warn() { echo -e "${YELLOW}  warn${RESET} $1" >&2; }
err()  { echo -e "${RED}  err${RESET} $1" >&2; }

# --- Parse arguments ---
BRANCH=""
JSON_OUTPUT=false
NO_MERGE=false
FORCE=false
ALL_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --no-merge)
      NO_MERGE=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --all)
      ALL_MODE=true
      shift
      ;;
    -*)
      err "Unknown flag: $1"
      exit 1
      ;;
    *)
      if [ -z "$BRANCH" ]; then
        BRANCH="$1"
      else
        err "Unexpected argument: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

# --- Usage check ---
if [ "$ALL_MODE" = false ] && [ -z "$BRANCH" ]; then
  echo "Usage: $(basename "$0") <branch> [--json] [--no-merge --force]" >&2
  echo "       $(basename "$0") --all [--no-merge --force]" >&2
  exit 1
fi

# --- Pre-flight: Verify inside a git repository ---
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  err "Not a git repository."
  exit 1
fi

# --- Pre-flight: Verify clean working tree ---
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  err "Working tree is dirty. Please clean your working tree first."
  exit 1
fi

# --- Single worktree cleanup function ---
# Returns: 0=success, 1=error, 3=conflict
cleanup_single() {
  local branch="$1"
  local json="$2"
  local no_merge="$3"
  local force="$4"

  # Resolve worktree path for this branch
  local wt_path=""
  local current_path=""
  local current_branch=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
      if [[ -n "$current_path" && "$current_branch" == "$branch" ]]; then
        wt_path="$current_path"
        break
      fi
      current_path="${BASH_REMATCH[1]}"
      current_branch=""
    elif [[ "$line" =~ ^branch\ refs/heads/(.+)$ ]]; then
      current_branch="${BASH_REMATCH[1]}"
    fi
  done < <(git worktree list --porcelain 2>/dev/null)

  # Flush last entry
  if [[ -z "$wt_path" && -n "$current_path" && "$current_branch" == "$branch" ]]; then
    wt_path="$current_path"
  fi

  if [ -z "$wt_path" ]; then
    err "Branch not found in worktree list: $branch"
    return 1
  fi

  # --- Discard mode (--no-merge --force) ---
  if [ "$no_merge" = true ] && [ "$force" = true ]; then
    git worktree remove --force "$wt_path" >/dev/null 2>&1
    git branch -D "$branch" >/dev/null 2>&1
    ok "Worktree discarded: $branch"

    if [ "$json" = true ]; then
      printf '{"branch":"%s","action":"discarded"}\n' "$branch"
    fi
    return 0
  fi

  # --- Merge mode (default) ---
  # Attempt merge with --no-ff to preserve history
  if ! git merge "$branch" --no-ff -m "Merge worktree branch '$branch'" >/dev/null 2>&1; then
    # Merge conflict detected
    local conflict_files
    conflict_files=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
    git merge --abort 2>/dev/null || true

    err "Merge conflict with branch: $branch"
    if [ -n "$conflict_files" ]; then
      echo "Conflicting files:" >&2
      echo "$conflict_files" | while IFS= read -r f; do
        echo "  $f" >&2
      done
    fi
    return 3
  fi

  # Capture merge stats
  local merge_commit
  merge_commit=$(git rev-parse --short HEAD)

  local stat_line
  stat_line=$(git diff --stat HEAD~1 2>/dev/null | tail -1)

  local files_changed=0
  local insertions=0
  local deletions=0

  if [[ "$stat_line" =~ ([0-9]+)\ file ]]; then
    files_changed="${BASH_REMATCH[1]}"
  fi
  if [[ "$stat_line" =~ ([0-9]+)\ insertion ]]; then
    insertions="${BASH_REMATCH[1]}"
  fi
  if [[ "$stat_line" =~ ([0-9]+)\ deletion ]]; then
    deletions="${BASH_REMATCH[1]}"
  fi

  # Remove worktree and branch
  git worktree remove "$wt_path" >/dev/null 2>&1
  git branch -d "$branch" >/dev/null 2>&1

  # Output
  if [ "$json" = true ]; then
    printf '{"branch":"%s","merge_commit":"%s","files_changed":%d,"insertions":%d,"deletions":%d}\n' \
      "$branch" "$merge_commit" "$files_changed" "$insertions" "$deletions"
  else
    echo "" >&2
    echo "===========================================================" >&2
    echo " GSD Worktree Merged" >&2
    echo "===========================================================" >&2
    echo "  Branch:        $branch" >&2
    echo "  Merge commit:  $merge_commit" >&2
    echo "  Files changed: $files_changed" >&2
    echo "  Insertions:    +$insertions" >&2
    echo "  Deletions:     -$deletions" >&2
    echo "===========================================================" >&2
  fi

  return 0
}

# --- Batch mode (--all) ---
if [ "$ALL_MODE" = true ]; then
  LIST_SCRIPT="$SCRIPT_DIR/worktree-list.sh"
  if [ ! -x "$LIST_SCRIPT" ]; then
    err "worktree-list.sh not found or not executable at: $LIST_SCRIPT"
    exit 1
  fi

  # Get all GSD worktrees as JSON array
  local_json=$(bash "$LIST_SCRIPT" --json 2>/dev/null)
  # Parse branch names from JSON array
  branches=()
  while IFS= read -r b; do
    [ -n "$b" ] && branches+=("$b")
  done < <(echo "$local_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for wt in data:
    print(wt.get('branch', ''))
" 2>/dev/null)

  total=${#branches[@]}
  if [ "$total" -eq 0 ]; then
    ok "No active GSD worktrees to clean up."
    exit 0
  fi

  cleaned=0
  for b in "${branches[@]}"; do
    if cleanup_single "$b" "$JSON_OUTPUT" "$NO_MERGE" "$FORCE"; then
      cleaned=$((cleaned + 1))
    else
      rc=$?
      err "Stopped at worktree: $b (exit $rc)"
      echo "Cleaned $cleaned of $total worktrees" >&2
      exit "$rc"
    fi
  done

  echo "Cleaned $cleaned of $total worktrees" >&2
  exit 0
fi

# --- Single mode ---
cleanup_single "$BRANCH" "$JSON_OUTPUT" "$NO_MERGE" "$FORCE"
exit $?
