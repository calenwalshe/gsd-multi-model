#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# gsd worktree-list -- List active GSD worktrees
#
# Shows all git worktrees created by worktree-create.sh,
# identified by the gsd-worktree naming convention.
#
# Usage:
#   bin/worktree-list.sh          # human-readable table
#   bin/worktree-list.sh --json   # machine-readable output
# ============================================================

# --- ANSI color helpers with TTY detection ---
if [ -t 1 ]; then
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  BOLD=''
  DIM=''
  RESET=''
fi

# --- Parse arguments ---
JSON_OUTPUT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUTPUT=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# --- Verify inside a git repository ---
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Not a git repository." >&2
  exit 1
fi

# --- Collect GSD worktrees from porcelain output ---
declare -a WT_PATHS=()
declare -a WT_BRANCHES=()
declare -a WT_COMMITS=()
declare -a WT_AGES=()

CURRENT_PATH=""
CURRENT_BRANCH=""
CURRENT_COMMIT=""

while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
    # Save previous entry if it was a GSD worktree
    if [[ -n "$CURRENT_PATH" && "$CURRENT_PATH" == *gsd-worktree* ]]; then
      WT_PATHS+=("$CURRENT_PATH")
      WT_BRANCHES+=("$CURRENT_BRANCH")
      WT_COMMITS+=("$CURRENT_COMMIT")
      # Calculate age from directory mtime (Linux: stat -c, macOS: stat -f)
      if stat -c '%Y' "$CURRENT_PATH" >/dev/null 2>&1; then
        DIR_EPOCH=$(stat -c '%Y' "$CURRENT_PATH")
      else
        DIR_EPOCH=$(stat -f '%m' "$CURRENT_PATH" 2>/dev/null || echo "0")
      fi
      NOW_EPOCH=$(date +%s)
      AGE_SECONDS=$((NOW_EPOCH - DIR_EPOCH))
      WT_AGES+=("$AGE_SECONDS")
    fi
    CURRENT_PATH="${BASH_REMATCH[1]}"
    CURRENT_BRANCH=""
    CURRENT_COMMIT=""
  elif [[ "$line" =~ ^HEAD\ ([a-f0-9]+)$ ]]; then
    CURRENT_COMMIT="${BASH_REMATCH[1]}"
  elif [[ "$line" =~ ^branch\ refs/heads/(.+)$ ]]; then
    CURRENT_BRANCH="${BASH_REMATCH[1]}"
  fi
done < <(git worktree list --porcelain 2>/dev/null)

# Flush last entry
if [[ -n "$CURRENT_PATH" && "$CURRENT_PATH" == *gsd-worktree* ]]; then
  WT_PATHS+=("$CURRENT_PATH")
  WT_BRANCHES+=("$CURRENT_BRANCH")
  WT_COMMITS+=("$CURRENT_COMMIT")
  if stat -c '%Y' "$CURRENT_PATH" >/dev/null 2>&1; then
    DIR_EPOCH=$(stat -c '%Y' "$CURRENT_PATH")
  else
    DIR_EPOCH=$(stat -f '%m' "$CURRENT_PATH" 2>/dev/null || echo "0")
  fi
  NOW_EPOCH=$(date +%s)
  AGE_SECONDS=$((NOW_EPOCH - DIR_EPOCH))
  WT_AGES+=("$AGE_SECONDS")
fi

COUNT=${#WT_PATHS[@]}

# --- Format age for human display ---
format_age() {
  local seconds=$1
  if [ "$seconds" -lt 60 ]; then
    echo "${seconds}s ago"
  elif [ "$seconds" -lt 3600 ]; then
    echo "$((seconds / 60))m ago"
  elif [ "$seconds" -lt 86400 ]; then
    echo "$((seconds / 3600))h ago"
  else
    echo "$((seconds / 86400))d ago"
  fi
}

# --- Output ---
if [ "$JSON_OUTPUT" = true ]; then
  # Machine-readable JSON array
  printf '['
  for i in $(seq 0 $((COUNT - 1))); do
    [ "$i" -gt 0 ] && printf ','
    printf '{"branch":"%s","path":"%s","commit":"%s","age_seconds":%d}' \
      "${WT_BRANCHES[$i]}" "${WT_PATHS[$i]}" "${WT_COMMITS[$i]}" "${WT_AGES[$i]}"
  done
  printf ']\n'
else
  if [ "$COUNT" -eq 0 ]; then
    echo "No active GSD worktrees."
  else
    echo -e "${BOLD}GSD Worktrees ($COUNT active):${RESET}"
    printf "  %-30s %-50s %s\n" "Branch" "Path" "Age"
    for i in $(seq 0 $((COUNT - 1))); do
      AGE_STR=$(format_age "${WT_AGES[$i]}")
      printf "  %-30s %-50s %s\n" "${WT_BRANCHES[$i]}" "${WT_PATHS[$i]}" "$AGE_STR"
    done
  fi
fi
