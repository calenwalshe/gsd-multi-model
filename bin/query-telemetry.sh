#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# query-telemetry.sh -- Telemetry query orchestrator
#
# Queries configured telemetry endpoints (logs, APIs, services)
# and produces structured output. Config-driven, opt-in.
#
# Usage:
#   bin/query-telemetry.sh                          # query all endpoints
#   bin/query-telemetry.sh --endpoint app-logs      # query single endpoint
#   bin/query-telemetry.sh --health                 # check endpoint reachability
#   bin/query-telemetry.sh --json-only              # suppress stderr output
#   bin/query-telemetry.sh --project-root PATH      # override project root
#
# Config (.planning/config.json):
#   {
#     "observability": {
#       "enabled": true,
#       "endpoints": {
#         "app-logs": {
#           "type": "docker",         // docker | http | file | journalctl
#           "container": "my-app",    // docker: container name
#           "url": "https://...",     // http: endpoint URL
#           "path": "/var/log/...",   // file: log file path
#           "unit": "my-service",     // journalctl: service unit
#           "lines": 100,            // max lines to retrieve
#           "filter": "ERROR|WARN",  // grep filter pattern
#           "timeout_seconds": 10,   // http timeout
#           "headers": {             // http headers (supports ${ENV_VAR})
#             "Authorization": "Bearer ${API_TOKEN}"
#           },
#           "response_path": ".[0:5]" // http: node expression for response
#         }
#       }
#     }
#   }
#
# Output:
#   stdout: JSON {"enabled":bool,"endpoints":{...},"results":[...],"summary":{...}}
#   stderr: Human-readable summary with ANSI colors
#   exit 0: always (unreachable endpoints produce warnings, not failures)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- ANSI color helpers (stderr is the human channel) ---
QUIET="false"
setup_colors() {
  if [ "$QUIET" = "true" ]; then
    RED=''; GREEN=''; YELLOW=''; BOLD=''; DIM=''; RESET=''
  elif [ -t 2 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
  else
    RED=''; GREEN=''; YELLOW=''; BOLD=''; DIM=''; RESET=''
  fi
}

log()  { [ "$QUIET" = "false" ] && echo -e "$1" >&2 || true; }
ok()   { log "${GREEN}  OK${RESET} $1"; }
warn() { log "${YELLOW}  WARN${RESET} $1"; }
err()  { log "${RED}  ERR${RESET} $1"; }

# --- Parse arguments ---
SINGLE_ENDPOINT=""
HEALTH_MODE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --endpoint)      SINGLE_ENDPOINT="$2"; shift 2 ;;
    --json-only)     QUIET="true"; shift ;;
    --project-root)  PROJECT_ROOT="$2"; shift 2 ;;
    --health)        HEALTH_MODE="true"; shift ;;
    *)               shift ;;
  esac
done

setup_colors

# --- Load config ---
CONFIG_FILE="$PROJECT_ROOT/.planning/config.json"
OBS_ENABLED="false"
OBS_ENDPOINTS="{}"

if [ -f "$CONFIG_FILE" ]; then
  OBS_JSON=$(node -e "
    const c = JSON.parse(require('fs').readFileSync('$CONFIG_FILE','utf8'));
    const o = c.observability || {};
    console.log(JSON.stringify({
      enabled: o.enabled !== undefined ? o.enabled : false,
      endpoints: o.endpoints || {}
    }));
  " 2>/dev/null || echo '{"enabled":false,"endpoints":{}}')

  OBS_ENABLED=$(echo "$OBS_JSON" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).enabled))")
  OBS_ENDPOINTS=$(echo "$OBS_JSON" | node -e "process.stdout.write(JSON.stringify(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).endpoints))")
fi

# --- If observability disabled or missing, output disabled JSON and exit ---
if [ "$OBS_ENABLED" = "false" ]; then
  echo '{"enabled":false,"endpoints":{},"results":[],"summary":{"total":0,"success":0,"failed":0}}'
  exit 0
fi

# --- Environment variable substitution ---
resolve_env_vars() {
  local input="$1"
  local result="$input"
  # Match ${VAR_NAME} patterns and replace with env values
  while [[ "$result" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
    local var_name="${BASH_REMATCH[1]}"
    local var_value="${!var_name:-}"
    result="${result/\$\{$var_name\}/$var_value}"
  done
  echo "$result"
}

# --- Endpoint dispatch functions ---

query_file() {
  local path="$1" lines="${2:-50}" filter="${3:-}"

  if [ ! -f "$path" ]; then
    echo '{"lines":[],"error":"file not found: '"$path"'"}'
    return
  fi

  local output
  output=$(tail -n "$lines" "$path" 2>/dev/null) || {
    echo '{"lines":[],"error":"failed to read: '"$path"'"}'
    return
  }

  if [ -n "$filter" ]; then
    output=$(echo "$output" | grep -E "$filter" || true)
  fi

  node -e "
    const lines = process.argv[1].split('\n').filter(Boolean);
    console.log(JSON.stringify({lines: lines, error: null}));
  " "$output"
}

query_http() {
  local url="$1" timeout="${2:-10}" headers_json="${3:-{}}" response_path="${4:-}"

  # Resolve env vars in URL
  url=$(resolve_env_vars "$url")

  # Build curl header args
  local curl_args=(-s --max-time "$timeout")

  # Parse headers and add to curl args
  local header_count
  header_count=$(node -e "
    const h = JSON.parse(process.argv[1]);
    console.log(Object.keys(h).length);
  " "$headers_json" 2>/dev/null || echo "0")

  if [ "$header_count" -gt 0 ]; then
    local header_lines
    header_lines=$(node -e "
      const h = JSON.parse(process.argv[1]);
      Object.entries(h).forEach(([k,v]) => console.log(k + ': ' + v));
    " "$headers_json" 2>/dev/null || true)

    while IFS= read -r header_line; do
      # Resolve env vars in header values
      header_line=$(resolve_env_vars "$header_line")
      curl_args+=(-H "$header_line")
    done <<< "$header_lines"
  fi

  local output
  output=$(curl "${curl_args[@]}" "$url" 2>/dev/null) || {
    echo '{"lines":[],"error":"request failed or timed out: '"$url"'"}'
    return
  }

  # If response_path specified, extract via node
  if [ -n "$response_path" ]; then
    output=$(node -e "
      const data = JSON.parse(process.argv[1]);
      const result = eval('data' + process.argv[2]);
      console.log(JSON.stringify(result, null, 2));
    " "$output" "$response_path" 2>/dev/null || echo "$output")
  fi

  node -e "
    const lines = process.argv[1].split('\n').filter(Boolean);
    console.log(JSON.stringify({lines: lines, error: null}));
  " "$output"
}

query_docker() {
  local container="$1" lines="${2:-100}" filter="${3:-}"

  if ! command -v docker &>/dev/null; then
    echo '{"lines":[],"error":"docker not available"}'
    return
  fi

  local output
  output=$(docker logs --tail "$lines" "$container" 2>&1) || {
    echo '{"lines":[],"error":"failed to query container: '"$container"'"}'
    return
  }

  if [ -n "$filter" ]; then
    output=$(echo "$output" | grep -E "$filter" || true)
  fi

  node -e "
    const lines = process.argv[1].split('\n').filter(Boolean);
    console.log(JSON.stringify({lines: lines, error: null}));
  " "$output"
}

query_journalctl() {
  local unit="$1" lines="${2:-50}" filter="${3:-}"

  if ! command -v journalctl &>/dev/null; then
    echo '{"lines":[],"error":"journalctl not available"}'
    return
  fi

  local output
  output=$(journalctl -u "$unit" -n "$lines" --no-pager 2>&1) || {
    echo '{"lines":[],"error":"failed to query unit: '"$unit"'"}'
    return
  }

  if [ -n "$filter" ]; then
    output=$(echo "$output" | grep -E "$filter" || true)
  fi

  node -e "
    const lines = process.argv[1].split('\n').filter(Boolean);
    console.log(JSON.stringify({lines: lines, error: null}));
  " "$output"
}

# --- Health check functions ---

health_file() {
  local path="$1"
  [ -f "$path" ] && echo "true" || echo "false"
}

health_http() {
  local url="$1" timeout="${2:-5}"
  url=$(resolve_env_vars "$url")
  curl -s --max-time "$timeout" --head "$url" &>/dev/null && echo "true" || echo "false"
}

health_docker() {
  local container="$1"
  if ! command -v docker &>/dev/null; then
    echo "false"
    return
  fi
  docker inspect "$container" &>/dev/null && echo "true" || echo "false"
}

health_journalctl() {
  local unit="$1"
  if ! command -v systemctl &>/dev/null; then
    echo "false"
    return
  fi
  systemctl is-active "$unit" &>/dev/null && echo "true" || echo "false"
}

# --- Get endpoint list ---
ENDPOINT_NAMES=$(node -e "
  const endpoints = JSON.parse(process.argv[1]);
  console.log(Object.keys(endpoints).join('\n'));
" "$OBS_ENDPOINTS" 2>/dev/null || echo "")

# Filter to single endpoint if specified
if [ -n "$SINGLE_ENDPOINT" ]; then
  if echo "$ENDPOINT_NAMES" | grep -qx "$SINGLE_ENDPOINT"; then
    ENDPOINT_NAMES="$SINGLE_ENDPOINT"
  else
    ENDPOINT_NAMES=""
  fi
fi

# --- Main loop ---
RESULTS="[]"
SUCCESS_COUNT=0
FAILED_COUNT=0

log "\n${BOLD}=== TELEMETRY QUERY ===${RESET}\n"

while IFS= read -r ep_name; do
  [ -z "$ep_name" ] && continue

  # Get endpoint config
  EP_CONFIG=$(node -e "
    const endpoints = JSON.parse(process.argv[1]);
    console.log(JSON.stringify(endpoints[process.argv[2]] || {}));
  " "$OBS_ENDPOINTS" "$ep_name")

  EP_TYPE=$(node -e "process.stdout.write(JSON.parse(process.argv[1]).type || 'unknown')" "$EP_CONFIG")

  if [ "$HEALTH_MODE" = "true" ]; then
    # Health check mode
    local_reachable="false"
    case "$EP_TYPE" in
      file)
        local_path=$(node -e "process.stdout.write(JSON.parse(process.argv[1]).path || '')" "$EP_CONFIG")
        local_reachable=$(health_file "$local_path")
        ;;
      http)
        local_url=$(node -e "process.stdout.write(JSON.parse(process.argv[1]).url || '')" "$EP_CONFIG")
        local_timeout=$(node -e "process.stdout.write(String(JSON.parse(process.argv[1]).timeout_seconds || 5))" "$EP_CONFIG")
        local_reachable=$(health_http "$local_url" "$local_timeout")
        ;;
      docker)
        local_container=$(node -e "process.stdout.write(JSON.parse(process.argv[1]).container || '')" "$EP_CONFIG")
        local_reachable=$(health_docker "$local_container")
        ;;
      journalctl)
        local_unit=$(node -e "process.stdout.write(JSON.parse(process.argv[1]).unit || '')" "$EP_CONFIG")
        local_reachable=$(health_journalctl "$local_unit")
        ;;
      *)
        local_reachable="false"
        ;;
    esac

    if [ "$local_reachable" = "true" ]; then
      ok "$ep_name ($EP_TYPE) -- reachable"
    else
      warn "$ep_name ($EP_TYPE) -- unreachable"
    fi

    RESULTS=$(node -e "
      const results = JSON.parse(process.argv[1]);
      results.push({
        name: process.argv[2],
        type: process.argv[3],
        reachable: process.argv[4] === 'true'
      });
      console.log(JSON.stringify(results));
    " "$RESULTS" "$ep_name" "$EP_TYPE" "$local_reachable")
  else
    # Query mode
    local_result='{"lines":[],"error":"unknown endpoint type: '"$EP_TYPE"'"}'

    case "$EP_TYPE" in
      file)
        local_path=$(node -e "process.stdout.write(JSON.parse(process.argv[1]).path || '')" "$EP_CONFIG")
        local_lines=$(node -e "process.stdout.write(String(JSON.parse(process.argv[1]).lines || 50))" "$EP_CONFIG")
        local_filter=$(node -e "process.stdout.write(JSON.parse(process.argv[1]).filter || '')" "$EP_CONFIG")
        local_result=$(query_file "$local_path" "$local_lines" "$local_filter")
        ;;
      http)
        local_url=$(node -e "process.stdout.write(JSON.parse(process.argv[1]).url || '')" "$EP_CONFIG")
        local_timeout=$(node -e "process.stdout.write(String(JSON.parse(process.argv[1]).timeout_seconds || 10))" "$EP_CONFIG")
        local_headers=$(node -e "process.stdout.write(JSON.stringify(JSON.parse(process.argv[1]).headers || {}))" "$EP_CONFIG")
        local_rpath=$(node -e "process.stdout.write(JSON.parse(process.argv[1]).response_path || '')" "$EP_CONFIG")
        local_result=$(query_http "$local_url" "$local_timeout" "$local_headers" "$local_rpath")
        ;;
      docker)
        local_container=$(node -e "process.stdout.write(JSON.parse(process.argv[1]).container || '')" "$EP_CONFIG")
        local_lines=$(node -e "process.stdout.write(String(JSON.parse(process.argv[1]).lines || 100))" "$EP_CONFIG")
        local_filter=$(node -e "process.stdout.write(JSON.parse(process.argv[1]).filter || '')" "$EP_CONFIG")
        local_result=$(query_docker "$local_container" "$local_lines" "$local_filter")
        ;;
      journalctl)
        local_unit=$(node -e "process.stdout.write(JSON.parse(process.argv[1]).unit || '')" "$EP_CONFIG")
        local_lines=$(node -e "process.stdout.write(String(JSON.parse(process.argv[1]).lines || 50))" "$EP_CONFIG")
        local_filter=$(node -e "process.stdout.write(JSON.parse(process.argv[1]).filter || '')" "$EP_CONFIG")
        local_result=$(query_journalctl "$local_unit" "$local_lines" "$local_filter")
        ;;
    esac

    # Extract lines and error from result
    local_result_lines=$(echo "$local_result" | node -e "process.stdout.write(JSON.stringify(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).lines || []))" 2>/dev/null || echo "[]")
    local_result_error=$(echo "$local_result" | node -e "process.stdout.write(JSON.stringify(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).error))" 2>/dev/null || echo "null")
    local_line_count=$(node -e "console.log(JSON.parse(process.argv[1]).length)" "$local_result_lines" 2>/dev/null || echo "0")

    if [ "$local_result_error" = "null" ]; then
      ok "$ep_name ($EP_TYPE) -- $local_line_count lines"
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
      warn "$ep_name ($EP_TYPE) -- $local_result_error"
      FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    RESULTS=$(node -e "
      const results = JSON.parse(process.argv[1]);
      results.push({
        name: process.argv[2],
        type: process.argv[3],
        lines: JSON.parse(process.argv[4]),
        error: JSON.parse(process.argv[5])
      });
      console.log(JSON.stringify(results));
    " "$RESULTS" "$ep_name" "$EP_TYPE" "$local_result_lines" "$local_result_error")
  fi
done <<< "$ENDPOINT_NAMES"

# --- Count totals ---
TOTAL_COUNT=$((SUCCESS_COUNT + FAILED_COUNT))

# --- Output JSON to stdout ---
node -e "
  const result = {
    enabled: true,
    endpoints: JSON.parse(process.argv[1]),
    results: JSON.parse(process.argv[2]),
    summary: {
      total: parseInt(process.argv[3]),
      success: parseInt(process.argv[4]),
      failed: parseInt(process.argv[5])
    }
  };
  console.log(JSON.stringify(result, null, 2));
" "$OBS_ENDPOINTS" "$RESULTS" "$TOTAL_COUNT" "$SUCCESS_COUNT" "$FAILED_COUNT"

# --- Human summary to stderr ---
log ""
if [ "$HEALTH_MODE" = "true" ]; then
  log "${BOLD}=== HEALTH CHECK COMPLETE ===${RESET}\n"
else
  log "${BOLD}=== TELEMETRY QUERY COMPLETE ===${RESET} ($SUCCESS_COUNT success, $FAILED_COUNT failed)\n"
fi

exit 0
