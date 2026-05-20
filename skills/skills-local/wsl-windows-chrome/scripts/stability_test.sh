#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

# Default values
TEST_COUNT=20
URL=""
BROWSER="${WSL_WINDOWS_CHROME_BROWSER:-chrome}"
WINDOWS_USER_DATA_DIR="${WSL_WINDOWS_CHROME_USER_DATA_DIR:-}"
CDP_PORT="${WSL_WINDOWS_CHROME_CDP_PORT:-9222}"
RELAY_PORT="${WSL_WINDOWS_CHROME_RELAY_PORT:-39222}"
ALLOW_FALLBACK=false
VERBOSE=false
JSON_OUTPUT=false
LOGS_DIR=""

# Result tracking
declare -a TEST_RESULTS
DIRECT_SUCCESS=0
RELAY_SUCCESS=0
FALLBACK_COUNT=0
FAILED_COUNT=0
TOTAL_SUCCESS=0
TOTAL_TIME=0
declare -A FAILURE_REASONS

usage() {
  cat <<'USAGE'
Usage: stability_test.sh [options]

Stability test for WSL-Windows-Chrome attach.

Runs multiple attach tests and reports success rate, failure reasons, and timing.

Options:
  --count <n>                Number of test iterations (default: 20)
  --url <url>                URL to navigate after attach
  --browser <chrome|edge>    Select the Windows browser family
  --port <port>              Override the Windows CDP port (default: 9222)
  --user-data-dir <path>     Override the Windows automation user-data-dir
  --relay-port <port>        Override the WSL-visible relay port (default: 39222)
  --allow-fallback           Allow fallback to fresh browser (not recommended)
  --logs-dir <path>          Directory to save logs (default: logs/stability)
  --json                     Output results as JSON
  --verbose                  Print extra diagnostics
  --help                     Show this help
USAGE
}

log() {
  wsl_windows_chrome_log "$@"
}

# Print a single test result
print_test_result() {
  local index="$1"
  local result="$2"
  local time="$3"
  local mode="$4"
  local reason="$5"

  printf "  Test %2d: " "$index"
  case "$result" in
    "success")
      echo -ne "\033[32mPASS\033[0m"
      ;;
    "fallback")
      echo -ne "\033[33mFALLBACK\033[0m"
      ;;
    "failed")
      echo -ne "\033[31mFAIL\033[0m"
      ;;
  esac
  printf " (%5.2fs) - %s" "$time" "$mode"
  if [[ -n "$reason" ]]; then
    printf " - %s" "$reason"
  fi
  echo ""
}

# Print human-readable results
print_results() {
  echo "=== WSL Windows Chrome Stability Test ==="
  echo ""
  echo "Browser: $BROWSER_LABEL"
  echo "CDP Port: $REQUESTED_CDP_PORT"
  echo "Test Count: $TEST_COUNT"
  echo "Allow Fallback: $ALLOW_FALLBACK"
  if [[ -n "$URL" ]]; then
    echo "Test URL: $URL"
  fi
  echo ""
  echo "Test Results:"

  for ((i = 0; i < ${#TEST_RESULTS[@]}; i++)); do
    IFS='|' read -r result time mode reason <<<"${TEST_RESULTS[$i]}"
    print_test_result "$((i + 1))" "$result" "$time" "$mode" "$reason"
  done

  echo ""
  echo "Summary:"
  echo "  Total Tests: $TEST_COUNT"
  echo "  Success (Direct): $DIRECT_SUCCESS"
  echo "  Success (Relay): $RELAY_SUCCESS"
  echo "  Total Success: $TOTAL_SUCCESS"
  echo "  Fallback: $FALLBACK_COUNT"
  echo "  Failed: $FAILED_COUNT"
  echo ""
  if [[ "$TEST_COUNT" -gt 0 ]]; then
    success_rate=$(awk "BEGIN { printf \"%.2f\", ($TOTAL_SUCCESS / $TEST_COUNT) * 100 }")
    echo "  Success Rate: $success_rate%"
  fi
  if [[ "$TOTAL_SUCCESS" -gt 0 ]]; then
    avg_time=$(awk "BEGIN { printf \"%.2f\", $TOTAL_TIME / $TOTAL_SUCCESS }")
    echo "  Average Time: ${avg_time}s"
  fi

  if [[ ${#FAILURE_REASONS[@]} -gt 0 ]]; then
    echo ""
    echo "Failure Reasons:"
    for reason in "${!FAILURE_REASONS[@]}"; do
      echo "  - $reason: ${FAILURE_REASONS[$reason]} times"
    done
  fi

  if [[ -n "$LOGS_DIR" ]]; then
    echo ""
    echo "Logs saved to: $LOGS_DIR"
  fi

  echo ""
  if [[ "$TOTAL_SUCCESS" -eq "$TEST_COUNT" ]]; then
    echo -e "Overall: \033[32mEXCELLENT\033[0m - All tests passed!"
  elif [[ "$TOTAL_SUCCESS" -ge $((TEST_COUNT * 9 / 10)) ]]; then
    echo -e "Overall: \033[32mGOOD\033[0m - High stability"
  elif [[ "$TOTAL_SUCCESS" -ge $((TEST_COUNT * 7 / 10)) ]]; then
    echo -e "Overall: \033[33mFAIR\033[0m - Moderate stability"
  else
    echo -e "Overall: \033[31mPOOR\033[0m - Low stability, investigate issues"
  fi
}

# Print results as JSON
print_results_json() {
  local tests_json=""
  local first=true

  for ((i = 0; i < ${#TEST_RESULTS[@]}; i++)); do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      tests_json="$tests_json,"
    fi

    IFS='|' read -r result time mode reason <<<"${TEST_RESULTS[$i]}"
    tests_json="$tests_json"
    tests_json="$tests_json$(printf '{"index":%d,"result":"%s","time":%.2f,"mode":"%s","reason":"%s"}' \
      "$((i + 1))" \
      "$result" \
      "$time" \
      "$mode" \
      "$(printf '%s' "$reason" | sed 's/"/\\"/g')")"
  done

  local failure_reasons_json=""
  first=true
  for reason in "${!FAILURE_REASONS[@]}"; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      failure_reasons_json="$failure_reasons_json,"
    fi
    failure_reasons_json="$failure_reasons_json$(printf '"%s":%d' "$(printf '%s' "$reason" | sed 's/"/\\"/g')" "${FAILURE_REASONS[$reason]}")"
  done

  local success_rate="0.00"
  local avg_time="0.00"
  if [[ "$TEST_COUNT" -gt 0 ]]; then
    success_rate=$(awk "BEGIN { printf \"%.2f\", ($TOTAL_SUCCESS / $TEST_COUNT) * 100 }")
  fi
  if [[ "$TOTAL_SUCCESS" -gt 0 ]]; then
    avg_time=$(awk "BEGIN { printf \"%.2f\", $TOTAL_TIME / $TOTAL_SUCCESS }")
  fi

  cat <<JSON
{
  "browser": "$BROWSER",
  "browser_label": "$BROWSER_LABEL",
  "cdp_port": $REQUESTED_CDP_PORT,
  "relay_port": $RELAY_PORT,
  "test_count": $TEST_COUNT,
  "allow_fallback": $(if [[ "$ALLOW_FALLBACK" == "true" ]]; then echo "true"; else echo "false"; fi),
  "test_url": $(if [[ -n "$URL" ]]; then printf '"%s"' "$URL"; else echo "null"; fi),
  "direct_success": $DIRECT_SUCCESS,
  "relay_success": $RELAY_SUCCESS,
  "total_success": $TOTAL_SUCCESS,
  "fallback_count": $FALLBACK_COUNT,
  "failed_count": $FAILED_COUNT,
  "success_rate": $success_rate,
  "average_time": $avg_time,
  "logs_dir": $(if [[ -n "$LOGS_DIR" ]]; then printf '"%s"' "$LOGS_DIR"; else echo "null"; fi),
  "failure_reasons": {$failure_reasons_json},
  "tests": [$tests_json]
}
JSON
}

# Run a single attach test
run_single_test() {
  local index="$1"
  local test_log_file="$LOGS_DIR/test_${index}.log"
  local start_time end_time elapsed_time
  local result=""
  local mode=""
  local reason=""

  start_time=$(date +%s.%N)

  # Build command arguments
  declare -a cmd_args=()
  cmd_args+=("--browser" "$BROWSER")
  cmd_args+=("--port" "$REQUESTED_CDP_PORT")
  cmd_args+=("--user-data-dir" "$WINDOWS_USER_DATA_DIR_RESOLVED")
  cmd_args+=("--relay-port" "$RELAY_PORT")
  if [[ -n "$URL" ]]; then
    cmd_args+=("--url" "$URL")
  fi
  if [[ "$VERBOSE" == "true" ]]; then
    cmd_args+=("--verbose")
  fi

  # Always run with --status first to check endpoints without attaching
  local status_output
  status_output="$(bash "$SCRIPT_DIR/attach_windows_logged_in_chrome.sh" --status "${cmd_args[@]}" 2>&1 || true)"

  # Parse preferred mode from status output
  local preferred_mode=""
  preferred_mode="$(echo "$status_output" | grep '^preferred_mode=' | cut -d= -f2 || true)"
  local direct_reachable="$(echo "$status_output" | grep '^direct_reachable=' | cut -d= -f2 || true)"
  local relay_reachable="$(echo "$status_output" | grep '^relay_reachable=' | cut -d= -f2 || true)"

  # Now try to attach
  local attach_output
  local attach_exit_code=0
  if bash "$SCRIPT_DIR/attach_windows_logged_in_chrome.sh" "${cmd_args[@]}" >"$test_log_file" 2>&1; then
    # Attach succeeded
    result="success"

    # Determine mode based on output or status
    if grep -q "Attached through localhost CDP attach" "$test_log_file" || \
       grep -q "Attached through gateway CDP attach" "$test_log_file" || \
       { [[ -n "$preferred_mode" ]] && [[ "$preferred_mode" != "relay" && "$preferred_mode" != "profile-relay" ]]; }; then
      mode="direct"
      DIRECT_SUCCESS=$((DIRECT_SUCCESS + 1))
    else
      mode="relay"
      RELAY_SUCCESS=$((RELAY_SUCCESS + 1))
    fi
    TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))

    # Clean up - close session
    wsl_windows_chrome_close_session "wsl-windows-chrome" 2>/dev/null || true
  else
    attach_exit_code=$?
    # Check if it fallback or failed
    if grep -q "ATTACH_MODE=fallback" "$test_log_file" 2>/dev/null; then
      result="fallback"
      mode="fallback"
      FALLBACK_COUNT=$((FALLBACK_COUNT + 1))
      reason="Fallback to fresh browser"
      FAILURE_REASONS["$reason"]=$((FAILURE_REASONS["$reason"] + 1))
      # Clean up fallback session
      wsl_windows_chrome_close_session "wsl-windows-chrome" 2>/dev/null || true
    else
      result="failed"
      mode="failed"
      FAILED_COUNT=$((FAILED_COUNT + 1))
      # Extract error reason
      reason="$(grep -E '(no reachable Windows automation browser|Playwright attach did not establish|Direct CDP attach failed)' "$test_log_file" | head -1 || true)"
      if [[ -z "$reason" ]]; then
        reason="Attach failed with exit code $attach_exit_code"
      fi
      FAILURE_REASONS["$reason"]=$((FAILURE_REASONS["$reason"] + 1))
    fi
  fi

  end_time=$(date +%s.%N)
  elapsed_time=$(awk "BEGIN { printf \"%.2f\", $end_time - $start_time }")

  if [[ "$result" == "success" ]]; then
    TOTAL_TIME=$(awk "BEGIN { printf \"%.2f\", $TOTAL_TIME + $elapsed_time }")
  fi

  # Store result: result|time|mode|reason
  TEST_RESULTS+=("$result|$elapsed_time|$mode|$reason")

  # Print immediate result if not JSON mode
  if [[ "$JSON_OUTPUT" != "true" ]]; then
    print_test_result "$index" "$result" "$elapsed_time" "$mode" "$reason"
  fi
}

while (($#)); do
  case "$1" in
    --count)
      TEST_COUNT="$2"
      shift 2
      ;;
    --url)
      URL="$2"
      shift 2
      ;;
    --browser)
      BROWSER="$2"
      shift 2
      ;;
    --port)
      CDP_PORT="$2"
      shift 2
      ;;
    --user-data-dir)
      WINDOWS_USER_DATA_DIR="$2"
      shift 2
      ;;
    --relay-port)
      RELAY_PORT="$2"
      shift 2
      ;;
    --allow-fallback)
      ALLOW_FALLBACK=true
      shift
      ;;
    --logs-dir)
      LOGS_DIR="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

BROWSER="$(wsl_windows_chrome_normalize_browser "$BROWSER")"
BROWSER_LABEL="$(wsl_windows_chrome_browser_label "$BROWSER")"
WINDOWS_USER_DATA_DIR_RESOLVED="$(wsl_windows_chrome_user_data_dir "$BROWSER" "$WINDOWS_USER_DATA_DIR")"
REQUESTED_CDP_PORT="$CDP_PORT"

# Setup logs directory if not specified
if [[ -z "$LOGS_DIR" ]]; then
  LOGS_DIR="$SCRIPT_DIR/../logs/stability/$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$LOGS_DIR"

# Check dependencies
if ! wsl_windows_chrome_has_cmd python3; then
  echo 'python3 not found in PATH; this helper needs python3.' >&2
  exit 1
fi
if ! wsl_windows_chrome_has_cmd playwright-cli; then
  echo 'playwright-cli not found in PATH.' >&2
  exit 1
fi

# Print header if not JSON
if [[ "$JSON_OUTPUT" != "true" ]]; then
  echo "=== WSL Windows Chrome Stability Test ==="
  echo "Running $TEST_COUNT tests..."
  echo ""
  echo "Test progress:"
fi

# Run all tests
for ((i = 1; i <= TEST_COUNT; i++)); do
  run_single_test "$i"
  # Small pause between tests
  sleep 0.5
done

# Print final results
if [[ "$JSON_OUTPUT" == "true" ]]; then
  print_results_json
else
  echo ""
  print_results
fi

# Exit with success if all tests passed (no fallbacks counted as success)
if [[ "$TOTAL_SUCCESS" -eq "$TEST_COUNT" ]]; then
  exit 0
else
  exit 1
fi
