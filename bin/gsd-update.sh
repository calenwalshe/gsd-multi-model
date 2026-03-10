#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# gsd-update -- Update GSD framework and reinstall addon
#
# Chains three stages in sequence:
#   1. npx get-shit-done-cc@latest --all --global (GSD update)
#   2. bash install.sh --force (addon reinstall)
#   3. Compatibility verification
#
# Must be run from within the gsd-multi-model repo (uses
# SCRIPT_DIR to locate install.sh and gsd-compat.json).
#
# Exit codes:
#   0 = success (all stages passed, version in compat range)
#   1 = GSD update failed (npx returned non-zero)
#   2 = addon reinstall failed (install.sh returned non-zero)
#   3 = compat warning (update succeeded but version outside
#       tested compatibility range in gsd-compat.json)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."

# --- ANSI color helpers (install.sh style, stdout, TTY on fd 1) ---
if [ -t 1 ]; then
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

ok()   { echo -e "${GREEN}  \xE2\x9C\x93${RESET} $1"; }
warn() { echo -e "${YELLOW}  \xE2\x9A\xA0${RESET} $1"; }
err()  { echo -e "${RED}  \xE2\x9C\x97${RESET} $1"; }

# --- Inline semver_compare (same implementation as install.sh) ---
# Returns: -1 (a < b), 0 (a == b), 1 (a > b)
# IFS is local -- does not affect caller
semver_compare() {
  local a="$1" b="$2"
  local IFS=.
  local a_parts=($a) b_parts=($b)
  local a_major=${a_parts[0]:-0} a_minor=${a_parts[1]:-0} a_patch=${a_parts[2]:-0}
  local b_major=${b_parts[0]:-0} b_minor=${b_parts[1]:-0} b_patch=${b_parts[2]:-0}

  if (( a_major != b_major )); then
    (( a_major > b_major )) && echo 1 || echo -1; return
  fi
  if (( a_minor != b_minor )); then
    (( a_minor > b_minor )) && echo 1 || echo -1; return
  fi
  if (( a_patch != b_patch )); then
    (( a_patch > b_patch )) && echo 1 || echo -1; return
  fi
  echo 0
}

# --- Pre-flight ---
if [ ! -f "$REPO_ROOT/install.sh" ]; then
  err "Cannot find install.sh at $REPO_ROOT/install.sh"
  exit 1
fi

# --- Record old version for comparison ---
VERSION_FILE="$HOME/.claude/get-shit-done/VERSION"
OLD_VERSION=""
[ -f "$VERSION_FILE" ] && OLD_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')

# --- Banner ---
echo ""
echo "==========================================================="
echo " gsd-update -- Update GSD + Reinstall Addon"
echo "==========================================================="
echo ""

# --- Stage 1: GSD Update ---
echo "==> Stage 1: Updating GSD framework..."
GSD_RC=0
npx -y get-shit-done-cc@latest --all --global || GSD_RC=$?

if [ "$GSD_RC" -ne 0 ]; then
  err "GSD update failed (exit code: $GSD_RC)"
  exit 1
fi
ok "GSD framework updated"
echo ""

# --- Stage 2: Addon Reinstall ---
echo "==> Stage 2: Reinstalling addon..."
INSTALL_RC=0
bash "$REPO_ROOT/install.sh" --force || INSTALL_RC=$?

if [ "$INSTALL_RC" -ne 0 ]; then
  err "Addon reinstall failed (exit code: $INSTALL_RC)"
  exit 2
fi
ok "Addon reinstalled"
echo ""

# --- Stage 3: Version Report + Compat Verification ---
echo "==> Stage 3: Verifying compatibility..."

if [ ! -f "$VERSION_FILE" ]; then
  warn "VERSION file not found after update"
  ok "Update complete (compat check skipped)"
  exit 0
fi

NEW_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')

# Validate VERSION format
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  warn "GSD VERSION has invalid format: $NEW_VERSION"
  exit 0
fi

ok "GSD version: v${NEW_VERSION}"

# Report version transition if changed
if [ -n "$OLD_VERSION" ] && [ "$OLD_VERSION" != "$NEW_VERSION" ]; then
  ok "Updated: v${OLD_VERSION} -> v${NEW_VERSION}"
fi

# Compat check (requires python3 and gsd-compat.json)
COMPAT_FILE="$REPO_ROOT/gsd-compat.json"

if ! command -v python3 &>/dev/null || [ ! -f "$COMPAT_FILE" ]; then
  warn "Cannot verify compatibility (python3 or gsd-compat.json missing)"
  exit 0
fi

COMPAT_MIN=$(python3 -c "import json; print(json.load(open('$COMPAT_FILE'))['gsd_compat']['min'])" 2>/dev/null) || { warn "Cannot read gsd-compat.json"; exit 0; }
COMPAT_MAX=$(python3 -c "import json; print(json.load(open('$COMPAT_FILE'))['gsd_compat']['max'])" 2>/dev/null) || { warn "Cannot read gsd-compat.json"; exit 0; }

CMP_MIN=$(semver_compare "$NEW_VERSION" "$COMPAT_MIN")
CMP_MAX=$(semver_compare "$NEW_VERSION" "$COMPAT_MAX")

if (( CMP_MIN >= 0 && CMP_MAX <= 0 )); then
  ok "GSD v${NEW_VERSION} is within tested range (${COMPAT_MIN} - ${COMPAT_MAX})"
else
  warn "GSD v${NEW_VERSION} is outside tested range (${COMPAT_MIN} - ${COMPAT_MAX})"
  echo ""
  echo "==========================================================="
  echo " UPDATE COMPLETE (with compatibility warning)"
  echo " GSD: v${NEW_VERSION}"
  echo "==========================================================="
  exit 3
fi

echo ""
echo "==========================================================="
echo " UPDATE COMPLETE"
echo " GSD: v${NEW_VERSION}"
echo "==========================================================="
exit 0
