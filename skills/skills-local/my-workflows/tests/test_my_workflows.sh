#!/usr/bin/env bash
# test_my_workflows.sh - behavior regression coverage

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${TEST_DIR}/../scripts"
MY_WORKFLOWS_SH="${SCRIPTS_DIR}/my_workflows.sh"

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

TEST_TMP_ROOT=""
FIXTURE_TG_DIR=""
FIXTURE_WORKTREES=""
FIXTURE_SCRIPTS=""
FIXTURE_LAUNCH_LOG=""

log_test() {
  printf '\n[TEST] %s\n' "$*"
}

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  printf '  [PASS] %s\n' "$*"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  printf '  [FAIL] %s\n' "$*" >&2
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if printf '%s\n' "${haystack}" | grep -Fq -- "${needle}"; then
    pass "${message}"
  else
    fail "${message}"
    printf '    expected to find: %s\n' "${needle}" >&2
    return 1
  fi
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"
  if [[ -f "${file}" ]] && grep -Fq -- "${needle}" "${file}"; then
    pass "${message}"
  else
    fail "${message}"
    printf '    file: %s\n    expected to find: %s\n' "${file}" "${needle}" >&2
    return 1
  fi
}

write_fake_launcher() {
  local launcher_path="$1"
  cat > "${launcher_path}" <<'EOF_LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail

launcher_name="$(basename "$0")"
log_path="${MY_WORKFLOWS_LAUNCH_LOG:?MY_WORKFLOWS_LAUNCH_LOG is required}"
worktree=""
task_slug=""
prompt_file=""
title=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --worktree)
      worktree="$2"
      shift 2
      ;;
    --task-slug)
      task_slug="$2"
      shift 2
      ;;
    --prompt-file)
      prompt_file="$2"
      shift 2
      ;;
    --title)
      title="$2"
      shift 2
      ;;
    --model|--reasoning-effort|--terminal-mode)
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --verbose|--interactive|--no-app-server-preflight|--exec)
      shift
      ;;
    *)
      printf 'unexpected launcher argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

[[ -d "${worktree}" ]] || { printf 'missing worktree: %s\n' "${worktree}" >&2; exit 1; }
[[ -f "${prompt_file}" ]] || { printf 'missing prompt: %s\n' "${prompt_file}" >&2; exit 1; }

printf '%s|worktree=%s|task=%s|prompt=%s|title=%s|dry=%s\n' \
  "${launcher_name}" "${worktree}" "${task_slug}" "${prompt_file}" "${title}" "${dry_run}" >> "${log_path}"
EOF_LAUNCHER
  chmod +x "${launcher_path}"
}

init_worker_repo() {
  local worker="$1"
  local worktree="${FIXTURE_WORKTREES}/${worker}"
  mkdir -p "${worktree}"
  git -C "${worktree}" init -q
}

setup_fixture() {
  cleanup_fixture
  TEST_TMP_ROOT="$(mktemp -d)"
  FIXTURE_TG_DIR="${TEST_TMP_ROOT}/tg-agent-gateway"
  FIXTURE_WORKTREES="${TEST_TMP_ROOT}/worktrees"
  FIXTURE_SCRIPTS="${TEST_TMP_ROOT}/scripts"
  FIXTURE_LAUNCH_LOG="${TEST_TMP_ROOT}/launch.log"

  mkdir -p "${FIXTURE_TG_DIR}" "${FIXTURE_WORKTREES}" "${FIXTURE_SCRIPTS}"
  : > "${FIXTURE_LAUNCH_LOG}"

  local worker
  for worker in cc2 cc3 cc4 cx2 cx3 cx4 cx5; do
    init_worker_repo "${worker}"
  done

  write_fake_launcher "${FIXTURE_SCRIPTS}/launch_claude_worker_terminal.sh"
  write_fake_launcher "${FIXTURE_SCRIPTS}/launch_codex_worker_terminal.sh"

  export MY_WORKFLOWS_TG_GATEWAY_DIR="${FIXTURE_TG_DIR}"
  export MY_WORKFLOWS_TG_GATEWAY_WORKTREES="${FIXTURE_WORKTREES}"
  export MY_WORKFLOWS_SCRIPTS_DIR="${FIXTURE_SCRIPTS}"
  export MY_WORKFLOWS_LAUNCH_LOG="${FIXTURE_LAUNCH_LOG}"
  export MY_WORKFLOWS_IGNORE_RUNTIME_BUSY=1
}

cleanup_fixture() {
  if [[ -n "${TEST_TMP_ROOT:-}" && -d "${TEST_TMP_ROOT}" ]]; then
    rm -rf "${TEST_TMP_ROOT}"
  fi
  TEST_TMP_ROOT=""
  FIXTURE_TG_DIR=""
  FIXTURE_WORKTREES=""
  FIXTURE_SCRIPTS=""
  FIXTURE_LAUNCH_LOG=""
  unset MY_WORKFLOWS_TG_GATEWAY_DIR
  unset MY_WORKFLOWS_TG_GATEWAY_WORKTREES
  unset MY_WORKFLOWS_SCRIPTS_DIR
  unset MY_WORKFLOWS_LAUNCH_LOG
  unset MY_WORKFLOWS_IGNORE_RUNTIME_BUSY
}

make_prompt() {
  local prompt_file="${TEST_TMP_ROOT}/source-prompt.md"
  printf 'Implement the requested demo change and run verification.\n' > "${prompt_file}"
  printf '%s\n' "${prompt_file}"
}

test_script_syntax() {
  log_test "Shell syntax"

  local errors
  if ! errors="$(bash -n "${MY_WORKFLOWS_SH}" 2>&1)"; then
    fail "my_workflows.sh has syntax errors: ${errors}"
    return 1
  fi

  pass "my_workflows.sh syntax is valid"
}

test_help() {
  log_test "Help output"

  local output
  output="$("${MY_WORKFLOWS_SH}" help 2>&1)"

  assert_contains "${output}" "Usage:" "help shows Usage"
  assert_contains "${output}" "orchestrate" "help lists orchestrate"
}

test_no_command_fails() {
  log_test "Missing command"

  local exit_code=0
  "${MY_WORKFLOWS_SH}" >/dev/null 2>&1 || exit_code="$?"

  if [[ "${exit_code}" -ne 0 ]]; then
    pass "missing command exits non-zero"
  else
    fail "missing command should exit non-zero"
  fi
}

test_unknown_command_fails() {
  log_test "Unknown command"

  local exit_code=0
  "${MY_WORKFLOWS_SH}" not-a-real-command >/dev/null 2>&1 || exit_code="$?"

  if [[ "${exit_code}" -ne 0 ]]; then
    pass "unknown command exits non-zero"
  else
    fail "unknown command should exit non-zero"
  fi
}

test_status_command_returns_zero() {
  log_test "Status command"

  setup_fixture
  local exit_code=0
  "${MY_WORKFLOWS_SH}" status >/dev/null 2>&1 || exit_code="$?"
  cleanup_fixture

  if [[ "${exit_code}" -eq 0 ]]; then
    pass "status exits zero in fixture"
  else
    fail "status should exit zero in fixture, got ${exit_code}"
  fi
}

test_missing_prompt_file_fails_even_dry_run() {
  log_test "orchestrate validates prompt file"

  setup_fixture
  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" orchestrate --task demo --prompt-file "${TEST_TMP_ROOT}/missing.md" --dry-run 2>&1)" || exit_code="$?"

  if [[ "${exit_code}" -ne 0 ]]; then
    pass "missing prompt exits non-zero"
  else
    fail "missing prompt should exit non-zero"
  fi
  assert_contains "${output}" "Prompt file not found" "missing prompt error is explicit"
  if [[ ! -s "${FIXTURE_LAUNCH_LOG}" ]]; then
    pass "missing prompt does not call launcher"
  else
    fail "missing prompt should not call launcher"
  fi
  cleanup_fixture
}

test_orchestrate_writes_handoffs_and_launches_workers() {
  log_test "orchestrate writes handoffs and launches visible workers"

  setup_fixture
  local prompt_file
  prompt_file="$(make_prompt)"

  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" orchestrate --task demo --prompt-file "${prompt_file}" 2>&1)" || exit_code="$?"

  if [[ "${exit_code}" -eq 0 ]]; then
    pass "orchestrate exits zero"
  else
    fail "orchestrate should exit zero: ${output}"
  fi

  local cc_handoff="${FIXTURE_TG_DIR}/.omx/claude-handoffs/cc3-demo.md"
  local observer_handoff="${FIXTURE_TG_DIR}/.omx/observers/cc2-demo-observer.md"
  assert_file_contains "${cc_handoff}" "Implement the requested demo change" "orchestrate writes implementation handoff"
  assert_file_contains "${observer_handoff}" "Read-Only Observer Handoff" "orchestrate writes observer handoff"
  assert_file_contains "${FIXTURE_LAUNCH_LOG}" "launch_claude_worker_terminal.sh|worktree=${FIXTURE_WORKTREES}/cc3|task=cc3-demo" "orchestrate launches cc3"
  assert_file_contains "${FIXTURE_LAUNCH_LOG}" "launch_claude_worker_terminal.sh|worktree=${FIXTURE_WORKTREES}/cc2|task=cc2-demo-observer" "orchestrate launches cc2 observer"
  cleanup_fixture
}

test_verbose_does_not_pollute_worker_selection() {
  log_test "verbose output does not pollute selected worker"

  setup_fixture
  touch "${FIXTURE_WORKTREES}/cc3/dirty.txt"
  local prompt_file
  prompt_file="$(make_prompt)"

  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" orchestrate --task review-smoke --prompt-file "${prompt_file}" --dry-run --verbose 2>&1)" || exit_code="$?"

  if [[ "${exit_code}" -eq 0 ]]; then
    pass "verbose dry-run exits zero"
  else
    fail "verbose dry-run should exit zero: ${output}"
  fi
  assert_contains "${output}" "Worker cc3 worktree is dirty" "verbose reports skipped dirty worker"
  assert_contains "${output}" "CC Worker: cc4" "verbose selection remains cc4"
  assert_contains "${output}" "--worktree ${FIXTURE_WORKTREES}/cc4" "dry-run launcher command uses clean cc4 worktree"
  cleanup_fixture
}

test_select_cx_rejects_cc_worker() {
  log_test "select-cx-worker rejects cc worker"

  setup_fixture
  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" select-cx-worker --worker cc4 --dry-run --verbose 2>&1)" || exit_code="$?"

  if [[ "${exit_code}" -ne 0 ]]; then
    pass "cc worker is rejected for cx repair"
  else
    fail "cc worker should be rejected for cx repair"
  fi
  assert_contains "${output}" "Requested worker must be a cx worker" "lane error mentions cx requirement"
  cleanup_fixture
}

test_repair_writes_handoff_and_launches_codex() {
  log_test "repair writes handoff and launches Codex worker"

  setup_fixture
  local prompt_file
  prompt_file="$(make_prompt)"

  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" repair --task fixdemo --prompt-file "${prompt_file}" 2>&1)" || exit_code="$?"

  if [[ "${exit_code}" -eq 0 ]]; then
    pass "repair exits zero"
  else
    fail "repair should exit zero: ${output}"
  fi

  local repair_handoff="${FIXTURE_TG_DIR}/.omx/claude-handoffs/cx3-fixdemo-repair.md"
  assert_file_contains "${repair_handoff}" "Codex Repair Handoff" "repair writes cx handoff"
  assert_file_contains "${FIXTURE_LAUNCH_LOG}" "launch_codex_worker_terminal.sh|worktree=${FIXTURE_WORKTREES}/cx3|task=cx3-fixdemo-repair" "repair launches cx3 Codex"
  cleanup_fixture
}

test_review_launches_cx2_only() {
  log_test "review launches cx2 only"

  setup_fixture
  local prompt_file
  prompt_file="$(make_prompt)"

  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" review --task reviewdemo --prompt-file "${prompt_file}" 2>&1)" || exit_code="$?"

  if [[ "${exit_code}" -eq 0 ]]; then
    pass "review exits zero"
  else
    fail "review should exit zero: ${output}"
  fi
  assert_file_contains "${FIXTURE_LAUNCH_LOG}" "launch_codex_worker_terminal.sh|worktree=${FIXTURE_WORKTREES}/cx2|task=cx2-reviewdemo-review" "review launches cx2"

  exit_code=0
  output="$("${MY_WORKFLOWS_SH}" review --task reviewdemo2 --prompt-file "${prompt_file}" --worker cx3 2>&1)" || exit_code="$?"
  if [[ "${exit_code}" -ne 0 ]]; then
    pass "review rejects non-cx2 worker"
  else
    fail "review should reject non-cx2 worker"
  fi
  assert_contains "${output}" "Review worker is fixed to cx2" "review error states cx2 boundary"
  cleanup_fixture
}

test_integrate_writes_candidate() {
  log_test "integrate writes master candidate"

  setup_fixture
  local prompt_file
  prompt_file="$(make_prompt)"

  local candidate_file
  local exit_code=0
  candidate_file="$("${MY_WORKFLOWS_SH}" integrate --task mergedemo --prompt-file "${prompt_file}" 2>/dev/null)" || exit_code="$?"

  if [[ "${exit_code}" -eq 0 ]]; then
    pass "integrate exits zero"
  else
    fail "integrate should exit zero"
  fi
  if [[ "${candidate_file}" == "${FIXTURE_TG_DIR}/.omx/integration-candidates/mergedemo.md" ]]; then
    pass "integrate prints candidate path on stdout"
  else
    fail "integrate should print only the candidate path, got: ${candidate_file}"
  fi
  assert_file_contains "${candidate_file}" "Master Integration Candidate" "integrate writes candidate file"
  cleanup_fixture
}

test_launcher_syntax() {
  log_test "Launcher syntax"

  local launcher
  for launcher in launch_codex_worker_terminal.sh launch_claude_worker_terminal.sh; do
    local launcher_path="${SCRIPTS_DIR}/${launcher}"
    if [[ ! -f "${launcher_path}" ]]; then
      fail "${launcher} should exist"
      continue
    fi

    local errors
    if ! errors="$(bash -n "${launcher_path}" 2>&1)"; then
      fail "${launcher} has syntax errors: ${errors}"
    else
      pass "${launcher} syntax is valid"
    fi
  done
}

run_all_tests() {
  printf '\n=== my_workflows.sh regression tests ===\n'

  test_script_syntax
  test_help
  test_no_command_fails
  test_unknown_command_fails
  test_status_command_returns_zero
  test_missing_prompt_file_fails_even_dry_run
  test_orchestrate_writes_handoffs_and_launches_workers
  test_verbose_does_not_pollute_worker_selection
  test_select_cx_rejects_cc_worker
  test_repair_writes_handoff_and_launches_codex
  test_review_launches_cx2_only
  test_integrate_writes_candidate
  test_launcher_syntax

  printf '\n=== Test results ===\n'
  printf 'Total: %d\n' "${TESTS_TOTAL}"
  printf 'Passed: %d\n' "${TESTS_PASSED}"
  printf 'Failed: %d\n' "${TESTS_FAILED}"

  if [[ "${TESTS_FAILED}" -eq 0 ]]; then
    printf '\nAll tests passed.\n'
    return 0
  fi

  printf '\nSome tests failed.\n' >&2
  return 1
}

trap cleanup_fixture EXIT

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_all_tests "$@"
fi
