#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Integration test: Full worktree lifecycle (create -> list -> cleanup)
#
# Validates all three scripts work together end-to-end
# in a temporary git repository.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE_SCRIPT="$SCRIPT_DIR/bin/worktree-create.sh"
LIST_SCRIPT="$SCRIPT_DIR/bin/worktree-list.sh"
CLEANUP_SCRIPT="$SCRIPT_DIR/bin/worktree-cleanup.sh"

PASS=0
FAIL=0

ok()  { echo "  ok  $1"; PASS=$((PASS + 1)); }
err() { echo "  err $1 -- $2"; FAIL=$((FAIL + 1)); }

cleanup() {
  rm -rf "$TEST_DIR" 2>/dev/null || true
}
trap cleanup EXIT

TEST_DIR=$(mktemp -d /tmp/gsd-lifecycle-test-XXXXXX)

# --- Helper: create a fresh test repo ---
make_repo() {
  local name="$1"
  local repo="$TEST_DIR/$name"
  mkdir -p "$repo" && cd "$repo"
  git init -q
  git commit --allow-empty -m "initial commit" -q
  echo "$repo"
}

echo "=== GSD Worktree Lifecycle Integration Tests ==="
echo ""

# -------------------------------------------------------
# Test 1: Create worktree (exit 0, dir exists, branch exists)
# -------------------------------------------------------
test_create() {
  echo "-- Create worktree --"
  local repo
  repo=$(make_repo "lifecycle")
  cd "$repo"

  local output
  output=$(bash "$CREATE_SCRIPT" --json 2>/dev/null)
  local rc=$?

  if [ "$rc" -eq 0 ]; then
    ok "worktree-create exits 0"
  else
    err "worktree-create" "exit code $rc"
    return
  fi

  # Extract branch and path from JSON
  WT_BRANCH=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['branch'])")
  WT_PATH=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['path'])")

  if [ -d "$WT_PATH" ]; then
    ok "worktree directory exists at $WT_PATH"
  else
    err "worktree-create" "directory not found: $WT_PATH"
  fi

  if git show-ref --verify --quiet "refs/heads/$WT_BRANCH" 2>/dev/null; then
    ok "worktree branch exists: $WT_BRANCH"
  else
    err "worktree-create" "branch not found: $WT_BRANCH"
  fi
}

# -------------------------------------------------------
# Test 2: Create with --json produces valid JSON
# -------------------------------------------------------
test_create_json() {
  echo "-- Create with --json --"
  local repo="$TEST_DIR/lifecycle"
  cd "$repo"

  # WT_BRANCH and WT_PATH set by test_create
  local output
  output=$(bash "$CREATE_SCRIPT" --json 2>/dev/null)
  if echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert all(k in d for k in ['branch','path','base_commit','base_ref'])" 2>/dev/null; then
    ok "create --json has all required fields"
  else
    err "create-json" "missing fields: $output"
  fi

  # Cleanup extra worktree
  local extra_path
  extra_path=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['path'])")
  local extra_branch
  extra_branch=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['branch'])")
  git worktree remove "$extra_path" --force 2>/dev/null || true
  git branch -D "$extra_branch" 2>/dev/null || true
}

# -------------------------------------------------------
# Test 3: Make a commit in the worktree
# -------------------------------------------------------
test_work_in_worktree() {
  echo "-- Work in worktree --"
  local repo="$TEST_DIR/lifecycle"
  cd "$repo"

  echo "lifecycle test content" > "$WT_PATH/lifecycle-file.txt"
  (cd "$WT_PATH" && git add lifecycle-file.txt && git commit -m "add lifecycle file" -q)
  if (cd "$WT_PATH" && git log --oneline | grep -q "add lifecycle file"); then
    ok "commit created in worktree"
  else
    err "worktree-commit" "commit not found"
  fi
}

# -------------------------------------------------------
# Test 4: List worktrees (human-readable shows it)
# -------------------------------------------------------
test_list_human() {
  echo "-- List worktrees (human) --"
  local repo="$TEST_DIR/lifecycle"
  cd "$repo"

  local output
  output=$(bash "$LIST_SCRIPT" 2>&1)
  if echo "$output" | grep -q "$WT_BRANCH"; then
    ok "worktree-list shows branch $WT_BRANCH"
  else
    err "worktree-list" "branch not found in output"
  fi
}

# -------------------------------------------------------
# Test 5: List worktrees (--json produces valid JSON array)
# -------------------------------------------------------
test_list_json() {
  echo "-- List worktrees (JSON) --"
  local repo="$TEST_DIR/lifecycle"
  cd "$repo"

  local output
  output=$(bash "$LIST_SCRIPT" --json 2>/dev/null)
  if echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d, list) and len(d) > 0" 2>/dev/null; then
    ok "worktree-list --json returns non-empty array"
  else
    err "worktree-list-json" "invalid JSON: $output"
  fi
}

# -------------------------------------------------------
# Test 6: Cleanup merges, removes worktree dir, deletes branch
# -------------------------------------------------------
test_cleanup_merge() {
  echo "-- Cleanup with merge --"
  local repo="$TEST_DIR/lifecycle"
  cd "$repo"

  if bash "$CLEANUP_SCRIPT" "$WT_BRANCH" 2>/dev/null; then
    ok "worktree-cleanup exits 0"
  else
    err "worktree-cleanup" "exit code $?"
    return
  fi

  # Merge commit exists, file is in main
  if [ -f "$repo/lifecycle-file.txt" ]; then
    ok "file merged into main branch"
  else
    err "cleanup-merge" "lifecycle-file.txt not found after merge"
  fi

  # Worktree dir removed
  if [ ! -d "$WT_PATH" ]; then
    ok "worktree directory removed"
  else
    err "cleanup-merge" "worktree directory still exists"
  fi

  # Branch deleted
  if ! git show-ref --verify --quiet "refs/heads/$WT_BRANCH" 2>/dev/null; then
    ok "worktree branch deleted"
  else
    err "cleanup-merge" "branch still exists"
  fi
}

# -------------------------------------------------------
# Test 7: Error case -- dirty tree exits 1
# -------------------------------------------------------
test_error_dirty() {
  echo "-- Error: dirty tree --"
  local repo
  repo=$(make_repo "dirty-lifecycle")
  cd "$repo"

  echo "dirty" > somefile.txt && git add somefile.txt

  if bash "$CREATE_SCRIPT" 2>/dev/null; then
    err "dirty-create" "should exit non-zero"
  else
    local rc=$?
    if [ "$rc" -eq 1 ]; then
      ok "create on dirty tree exits 1"
    else
      err "dirty-create" "expected exit 1, got $rc"
    fi
  fi
}

# -------------------------------------------------------
# Test 8: Error case -- branch already exists exits 2
# -------------------------------------------------------
test_error_branch_exists() {
  echo "-- Error: branch exists --"
  local repo
  repo=$(make_repo "branch-exists-lifecycle")
  cd "$repo"

  mkdir -p .planning/phases/99-test
  touch .planning/phases/99-test/99-01-PLAN.md
  git branch "gsd/phase-99/plan-01"

  if bash "$CREATE_SCRIPT" --task .planning/phases/99-test/99-01-PLAN.md 2>/dev/null; then
    err "branch-exists" "should exit non-zero"
  else
    local rc=$?
    if [ "$rc" -eq 2 ]; then
      ok "create with existing branch exits 2"
    else
      err "branch-exists" "expected exit 2, got $rc"
    fi
  fi
}

# -------------------------------------------------------
# Test 9: --no-merge --force discards without merging
# -------------------------------------------------------
test_discard() {
  echo "-- Discard (--no-merge --force) --"
  local repo
  repo=$(make_repo "discard-lifecycle")
  cd "$repo"

  local output
  output=$(bash "$CREATE_SCRIPT" --json 2>/dev/null)
  local discard_branch
  discard_branch=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['branch'])")
  local discard_path
  discard_path=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['path'])")

  # Make changes
  echo "discarded" > "$discard_path/discard.txt"
  (cd "$discard_path" && git add discard.txt && git commit -m "will discard" -q)

  # Discard
  if bash "$CLEANUP_SCRIPT" --no-merge --force "$discard_branch" 2>/dev/null; then
    ok "discard exits 0"
  else
    err "discard" "exit code $?"
    return
  fi

  if [ ! -d "$discard_path" ]; then
    ok "discard removes worktree directory"
  else
    err "discard" "worktree still exists"
  fi

  if [ ! -f "$repo/discard.txt" ]; then
    ok "discard does not merge changes"
  else
    err "discard" "discarded file found in main"
  fi
}

# -------------------------------------------------------
# Run all tests
# -------------------------------------------------------
echo ""
test_create
echo ""
test_create_json
echo ""
test_work_in_worktree
echo ""
test_list_human
echo ""
test_list_json
echo ""
test_cleanup_merge
echo ""
test_error_dirty
echo ""
test_error_branch_exists
echo ""
test_discard
echo ""

echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
