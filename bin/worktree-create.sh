#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# gsd worktree-create -- Create an isolated GSD worktree
#
# Creates a new git worktree on a uniquely named branch,
# suitable for parallel Codex execution.
#
# Usage:
#   bin/worktree-create.sh                           # auto-generate names
#   bin/worktree-create.sh --task path/to/PLAN.md    # derive from plan file
#   bin/worktree-create.sh --json                    # machine-readable output
#   bin/worktree-create.sh --base <commit>           # create from specific commit
# ============================================================

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
TASK_FILE=""
JSON_OUTPUT=false
BASE_REF="HEAD"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)
      TASK_FILE="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --base)
      BASE_REF="$2"
      shift 2
      ;;
    *)
      err "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# --- Pre-flight check 1: Verify inside a git repository ---
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  err "Not a git repository. Run this from inside a git repo."
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
REPO_NAME="$(basename "$REPO_ROOT")"

# --- Pre-flight check 2: Verify clean working tree ---
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  err "Working tree is dirty. Please clean your working tree first."
  err "  git stash  OR  git commit"
  exit 1
fi

# --- Derive branch name and worktree directory ---
if [ -n "$TASK_FILE" ]; then
  # Extract phase and plan numbers from filename like 04-01-PLAN.md
  PLAN_BASENAME="$(basename "$TASK_FILE")"
  if [[ "$PLAN_BASENAME" =~ ^([0-9]+)-([0-9]+)-PLAN\.md$ ]]; then
    PHASE_NUM="${BASH_REMATCH[1]}"
    PLAN_NUM="${BASH_REMATCH[2]}"
    BRANCH_NAME="gsd/phase-${PHASE_NUM}/plan-${PLAN_NUM}"
    WT_DIR_NAME="gsd-worktree-phase${PHASE_NUM}-plan${PLAN_NUM}"
  else
    err "Cannot parse plan file name: $PLAN_BASENAME"
    err "Expected format: NN-NN-PLAN.md (e.g., 04-01-PLAN.md)"
    exit 1
  fi
else
  # Auto-generate names using short hash + random suffix
  SHORT_HASH="$(git rev-parse --short=8 HEAD)"
  RANDOM_SUFFIX="$(head -c 2 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  BRANCH_NAME="gsd/worktree/${SHORT_HASH}-${RANDOM_SUFFIX}"
  WT_DIR_NAME="gsd-worktree-${SHORT_HASH}-${RANDOM_SUFFIX}"
fi

# --- Pre-flight check 3: Verify branch name not taken ---
# With --task: fail immediately if branch exists (no collision avoidance)
# Without --task: try collision avoidance with -2, -3, etc.
ORIGINAL_BRANCH="$BRANCH_NAME"
ORIGINAL_DIR="$WT_DIR_NAME"

if [ -n "$TASK_FILE" ]; then
  if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
    err "Branch already exists: $BRANCH_NAME"
    err "  Delete it first: git branch -D $BRANCH_NAME"
    exit 2
  fi
else
  # Collision avoidance for auto-generated names
  ATTEMPT=1
  while git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; do
    ATTEMPT=$((ATTEMPT + 1))
    if [ "$ATTEMPT" -gt 10 ]; then
      err "Could not find unique branch name after 10 attempts."
      exit 2
    fi
    BRANCH_NAME="${ORIGINAL_BRANCH}-${ATTEMPT}"
    WT_DIR_NAME="${ORIGINAL_DIR}-${ATTEMPT}"
  done
fi

# --- Pre-flight check 4: Verify no existing worktree at target path ---
WT_PATH="$(dirname "$REPO_ROOT")/$WT_DIR_NAME"

if [ -d "$WT_PATH" ]; then
  err "Worktree already exists at: $WT_PATH"
  err "  Remove it first: git worktree remove $WT_PATH"
  exit 2
fi

# --- Pre-flight check 5: Warn if >= 3 active GSD worktrees ---
GSD_WT_COUNT=$(git worktree list 2>/dev/null | grep -c "gsd-worktree" || true)
if [ "$GSD_WT_COUNT" -ge 3 ]; then
  warn "You have $GSD_WT_COUNT active GSD worktrees. Consider cleaning up old ones."
fi

# --- Resolve base commit ---
BASE_COMMIT="$(git rev-parse --short "$BASE_REF")"

# --- Create the worktree ---
git worktree add "$WT_PATH" -b "$BRANCH_NAME" "$BASE_REF" --quiet 2>/dev/null

ok "Worktree created successfully"

# --- Output ---
if [ "$JSON_OUTPUT" = true ]; then
  # Machine-readable JSON output (to stdout)
  printf '{"branch":"%s","path":"%s","base_commit":"%s","base_ref":"%s"}\n' \
    "$BRANCH_NAME" "$WT_PATH" "$BASE_COMMIT" "$BASE_REF"
else
  # Human-readable output (to stderr for info, key details to stdout)
  echo "" >&2
  echo "===========================================================" >&2
  echo " GSD Worktree Created" >&2
  echo "===========================================================" >&2
  echo "  Branch:    $BRANCH_NAME" >&2
  echo "  Path:      $WT_PATH" >&2
  echo "  Base:      $BASE_COMMIT ($BASE_REF)" >&2
  echo "  Command:   cd $WT_PATH" >&2
  echo "===========================================================" >&2
fi
