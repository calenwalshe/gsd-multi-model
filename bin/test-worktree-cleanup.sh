#!/usr/bin/env bash
set -euo pipefail

# Test suite for bin/worktree-cleanup.sh
# Uses temporary git repos to validate merge-back, conflict detection, and batch cleanup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/worktree-cleanup.sh"
CREATE_SCRIPT="$SCRIPT_DIR/worktree-create.sh"
LIST_SCRIPT="$SCRIPT_DIR/worktree-list.sh"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 -- $2"; FAIL=$((FAIL + 1)); }

cleanup() {
  rm -rf "$TEST_DIR" 2>/dev/null || true
}
trap cleanup EXIT

TEST_DIR=$(mktemp -d /tmp/gsd-wt-cleanup-test-XXXXXX)

# --- Test 1: No arguments exits 1 with usage ---
test_no_args() {
  local repo="$TEST_DIR/no-args-repo"
  mkdir -p "$repo" && cd "$repo"
  git init -q && git commit --allow-empty -m "init" -q
  if bash "$CLEANUP_SCRIPT" 2>/dev/null; then
    fail "no-args" "should exit 1"
  else
    local rc=$?
    if [ "$rc" -eq 1 ]; then
      pass "no-args exits 1"
    else
      fail "no-args" "expected exit 1, got $rc"
    fi
  fi
}

# --- Test 2: Dirty main working tree exits 1 ---
test_dirty_tree() {
  local repo="$TEST_DIR/dirty-repo"
  mkdir -p "$repo" && cd "$repo"
  git init -q && git commit --allow-empty -m "init" -q
  echo "dirty" > file.txt && git add file.txt
  if bash "$CLEANUP_SCRIPT" somebranch 2>/dev/null; then
    fail "dirty-tree" "should exit 1"
  else
    local rc=$?
    if [ "$rc" -eq 1 ]; then
      pass "dirty-tree exits 1"
    else
      fail "dirty-tree" "expected exit 1, got $rc"
    fi
  fi
}

# --- Test 3: Branch not found exits 1 ---
test_branch_not_found() {
  local repo="$TEST_DIR/no-branch-repo"
  mkdir -p "$repo" && cd "$repo"
  git init -q && git commit --allow-empty -m "init" -q
  if bash "$CLEANUP_SCRIPT" nonexistent-branch 2>/dev/null; then
    fail "branch-not-found" "should exit 1"
  else
    local rc=$?
    if [ "$rc" -eq 1 ]; then
      pass "branch-not-found exits 1"
    else
      fail "branch-not-found" "expected exit 1, got $rc"
    fi
  fi
}

# --- Test 4: Successful merge and cleanup ---
test_merge_cleanup() {
  local repo="$TEST_DIR/merge-repo"
  mkdir -p "$repo" && cd "$repo"
  git init -q && git commit --allow-empty -m "init" -q
  # Create a worktree
  local branch="gsd/test-merge"
  local wt_path="$TEST_DIR/gsd-worktree-merge"
  git worktree add "$wt_path" -b "$branch" -q 2>/dev/null
  # Make a commit in the worktree
  echo "new content" > "$wt_path/test-file.txt"
  (cd "$wt_path" && git add test-file.txt && git commit -m "add test file" -q)
  # Run cleanup
  if bash "$CLEANUP_SCRIPT" "$branch" 2>/dev/null; then
    pass "merge-cleanup exits 0"
  else
    fail "merge-cleanup" "exit code $?"
    return
  fi
  # Verify: merge commit exists, file is in main
  if [ -f "$repo/test-file.txt" ]; then
    pass "merge-cleanup file merged into main"
  else
    fail "merge-cleanup" "test-file.txt not found after merge"
  fi
  # Verify: worktree dir removed
  if [ ! -d "$wt_path" ]; then
    pass "merge-cleanup worktree directory removed"
  else
    fail "merge-cleanup" "worktree directory still exists"
  fi
  # Verify: branch deleted
  if ! git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    pass "merge-cleanup branch deleted"
  else
    fail "merge-cleanup" "branch still exists"
  fi
}

# --- Test 5: Merge conflict exits 3 ---
test_merge_conflict() {
  local repo="$TEST_DIR/conflict-repo"
  mkdir -p "$repo" && cd "$repo"
  git init -q
  echo "original" > conflict-file.txt
  git add conflict-file.txt && git commit -m "init" -q
  # Create worktree
  local branch="gsd/test-conflict"
  local wt_path="$TEST_DIR/gsd-worktree-conflict"
  git worktree add "$wt_path" -b "$branch" -q 2>/dev/null
  # Modify file in both main and worktree
  echo "main change" > "$repo/conflict-file.txt"
  git add conflict-file.txt && git commit -m "main change" -q
  echo "worktree change" > "$wt_path/conflict-file.txt"
  (cd "$wt_path" && git add conflict-file.txt && git commit -m "wt change" -q)
  # Run cleanup -- should fail with conflict
  if bash "$CLEANUP_SCRIPT" "$branch" 2>/dev/null; then
    fail "merge-conflict" "should exit 3"
  else
    local rc=$?
    if [ "$rc" -eq 3 ]; then
      pass "merge-conflict exits 3"
    else
      fail "merge-conflict" "expected exit 3, got $rc"
    fi
  fi
  # Verify merge was aborted (working tree should be clean)
  if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
    pass "merge-conflict merge was aborted cleanly"
  else
    fail "merge-conflict" "merge not properly aborted"
  fi
  # Cleanup
  git worktree remove "$wt_path" --force 2>/dev/null || true
  git branch -D "$branch" 2>/dev/null || true
}

# --- Test 6: --no-merge --force discards worktree ---
test_no_merge_force() {
  local repo="$TEST_DIR/discard-repo"
  mkdir -p "$repo" && cd "$repo"
  git init -q && git commit --allow-empty -m "init" -q
  local branch="gsd/test-discard"
  local wt_path="$TEST_DIR/gsd-worktree-discard"
  git worktree add "$wt_path" -b "$branch" -q 2>/dev/null
  # Make changes in worktree
  echo "discarded content" > "$wt_path/discard-file.txt"
  (cd "$wt_path" && git add discard-file.txt && git commit -m "wt commit" -q)
  # Discard without merging
  if bash "$CLEANUP_SCRIPT" --no-merge --force "$branch" 2>/dev/null; then
    pass "no-merge-force exits 0"
  else
    fail "no-merge-force" "exit code $?"
    return
  fi
  # Verify: changes NOT merged
  if [ ! -f "$repo/discard-file.txt" ]; then
    pass "no-merge-force changes not merged"
  else
    fail "no-merge-force" "discarded file found in main"
  fi
  # Verify: worktree and branch removed
  if [ ! -d "$wt_path" ]; then
    pass "no-merge-force worktree removed"
  else
    fail "no-merge-force" "worktree still exists"
  fi
  if ! git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
    pass "no-merge-force branch deleted"
  else
    fail "no-merge-force" "branch still exists"
  fi
}

# --- Test 7: --json output ---
test_json_output() {
  local repo="$TEST_DIR/json-repo"
  mkdir -p "$repo" && cd "$repo"
  git init -q && git commit --allow-empty -m "init" -q
  local branch="gsd/test-json"
  local wt_path="$TEST_DIR/gsd-worktree-json"
  git worktree add "$wt_path" -b "$branch" -q 2>/dev/null
  echo "json test" > "$wt_path/json-file.txt"
  (cd "$wt_path" && git add json-file.txt && git commit -m "json test" -q)
  local output
  output=$(bash "$CLEANUP_SCRIPT" "$branch" --json 2>/dev/null)
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "json-output" "exit code $rc"
    return
  fi
  if echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'branch' in d and 'merge_commit' in d" 2>/dev/null; then
    pass "json-output produces valid JSON with required fields"
  else
    fail "json-output" "invalid JSON: $output"
  fi
}

echo "=== worktree-cleanup.sh test suite ==="
test_no_args
test_dirty_tree
test_branch_not_found
test_merge_cleanup
test_merge_conflict
test_no_merge_force
test_json_output
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
