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
ORIGINAL_PATH="${PATH}"
FAKE_TMUX_DIR=""
FAKE_TMUX_LOG=""
FAKE_TMUX_SESSIONS=""
FAKE_TMUX_PANES=""

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

assert_file_not_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"
  if [[ -f "${file}" ]] && ! grep -Fq -- "${needle}" "${file}"; then
    pass "${message}"
  else
    fail "${message}"
    printf '    file: %s\n    should not contain: %s\n' "${file}" "${needle}" >&2
    return 1
  fi
}

write_fake_tmux() {
  local fake_dir="$1"
  mkdir -p "${fake_dir}"
  cat > "${fake_dir}/tmux" <<'EOF_TMUX'
#!/usr/bin/env bash
set -euo pipefail

log_path="${MY_WORKFLOWS_FAKE_TMUX_LOG:-}"
if [[ -n "${log_path}" ]]; then
  printf '%q' "$1" >> "${log_path}"
  for arg in "${@:2}"; do
    printf ' %q' "${arg}" >> "${log_path}"
  done
  printf '\n' >> "${log_path}"
fi

target_from_args() {
  local target=""
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -t)
        target="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  printf '%s\n' "${target}"
}

case "${1:-}" in
  has-session)
    target="$(target_from_args "$@")"
    printf '%s\n' "${MY_WORKFLOWS_FAKE_TMUX_SESSIONS:-}" | grep -Fxq -- "${target}"
    ;;
  display-message)
    target="$(target_from_args "$@")"
    format="${*: -1}"
    if [[ "${format}" == '#{pane_current_command}' ]]; then
      printf 'claude\n'
    elif [[ "${format}" == '#{pane_current_path}' ]]; then
      session="${target%%:*}"
      worker="unknown"
      if [[ "${session}" =~ ^claude-(cc[0-9]+)- ]]; then
        worker="${BASH_REMATCH[1]}"
      fi
      printf '%s/%s\n' "${MY_WORKFLOWS_TG_GATEWAY_WORKTREES:-/tmp/worktrees}" "${worker}"
    fi
    ;;
  capture-pane)
    printf '%s\n' "${MY_WORKFLOWS_FAKE_TMUX_CAPTURE:-● Summary
Changed Files
Verification
Token Usage}"
    ;;
  list-panes)
    printf '%s\n' "${MY_WORKFLOWS_FAKE_TMUX_PANES:-}"
    ;;
  load-buffer|paste-buffer|send-keys|list-sessions)
    if [[ "${1:-}" == "list-sessions" ]]; then
      printf '%s\n' "${MY_WORKFLOWS_FAKE_TMUX_SESSIONS:-}"
    fi
    ;;
  *)
    ;;
esac
EOF_TMUX
  chmod +x "${fake_dir}/tmux"
}

setup_fake_tmux() {
  local sessions="$1"
  local panes="${2:-}"
  FAKE_TMUX_DIR="${TEST_TMP_ROOT}/fake-bin"
  FAKE_TMUX_LOG="${TEST_TMP_ROOT}/fake-tmux.log"
  FAKE_TMUX_SESSIONS="${sessions}"
  FAKE_TMUX_PANES="${panes}"
  : > "${FAKE_TMUX_LOG}"
  write_fake_tmux "${FAKE_TMUX_DIR}"
  export PATH="${FAKE_TMUX_DIR}:${ORIGINAL_PATH}"
  export MY_WORKFLOWS_FAKE_TMUX_LOG="${FAKE_TMUX_LOG}"
  export MY_WORKFLOWS_FAKE_TMUX_SESSIONS="${FAKE_TMUX_SESSIONS}"
  export MY_WORKFLOWS_FAKE_TMUX_PANES="${FAKE_TMUX_PANES}"
  export MY_WORKFLOWS_FAKE_TMUX_CAPTURE='● Summary
Changed Files
Verification
Token Usage'
}

observe_report_path() {
  local task_slug="$1"
  printf '%s/.omx/observers/%s.result.md\n' "${FIXTURE_TG_DIR}" "${task_slug}"
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

  mkdir -p "${FIXTURE_TG_DIR}/data" "${FIXTURE_WORKTREES}" "${FIXTURE_SCRIPTS}"
  : > "${FIXTURE_LAUNCH_LOG}"

  local worker
  for worker in cc2 cc3 cc4 cc5 cc6 cc7 cc8 cc9 cc10 cx2 cx3 cx4 cx5; do
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
  unset MY_WORKFLOWS_FAKE_TMUX_LOG
  unset MY_WORKFLOWS_FAKE_TMUX_SESSIONS
  unset MY_WORKFLOWS_FAKE_TMUX_PANES
  unset MY_WORKFLOWS_FAKE_TMUX_CAPTURE
  unset MY_WORKFLOWS_OBSERVER_REPORT_SEND_LIMIT_BYTES
  PATH="${ORIGINAL_PATH}"
  FAKE_TMUX_DIR=""
  FAKE_TMUX_LOG=""
  FAKE_TMUX_SESSIONS=""
  FAKE_TMUX_PANES=""
}

enable_runtime_checks() {
  export MY_WORKFLOWS_IGNORE_RUNTIME_BUSY=0
}

init_gateway_db() {
  sqlite3 "${FIXTURE_TG_DIR}/data/gateway.sqlite" \
    "CREATE TABLE tasks (id TEXT PRIMARY KEY, status TEXT, worker TEXT, recommended_agent TEXT, process_id INTEGER, created_at TEXT);"
}

insert_task_row() {
  local id="$1"
  local worker="$2"
  local recommended_agent="$3"
  local status="$4"
  local process_id="${5:-}"
  local process_sql="NULL"
  if [[ -n "${process_id}" ]]; then
    process_sql="${process_id}"
  fi

  sqlite3 "${FIXTURE_TG_DIR}/data/gateway.sqlite" \
    "INSERT INTO tasks (id, status, worker, recommended_agent, process_id, created_at) VALUES ('${id}', '${status}', '${worker}', '${recommended_agent}', ${process_sql}, '2026-01-01T00:00:00Z');"
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
  if [[ ! -e "${FIXTURE_TG_DIR}/.omx" ]]; then
    pass "status does not create .omx artifacts"
  else
    fail "status should remain read-only and not create .omx artifacts"
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
  local observer_handoff="${FIXTURE_TG_DIR}/.omx/claude-handoffs/cc2-demo-observer.md"
  assert_file_contains "${cc_handoff}" "Implement the requested demo change" "orchestrate writes implementation handoff"
  assert_file_contains "${observer_handoff}" "Read-Only Observer Handoff" "orchestrate writes observer handoff"
  assert_file_contains "${observer_handoff}" "observe-group --task demo --workers cc3 --target-pane cx2:0.0" "observer handoff calls observe-group"
  assert_file_contains "${observer_handoff}" ".omx/observers/demo.result.md" "observer handoff records group result path"
  if [[ ! -e "${FIXTURE_TG_DIR}/plans/cc3-demo.md" && ! -e "${FIXTURE_TG_DIR}/plans/cc2-demo-observer.md" ]]; then
    pass "orchestrate does not write prompts to plans"
  else
    fail "orchestrate should not write prompts to plans"
  fi
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
  assert_contains "${output}" "worker=cc3" "verbose reports skipped dirty worker"
  assert_contains "${output}" "reasons=dirty" "verbose reports dirty reason"
  assert_contains "${output}" "CC Worker: cc4" "verbose selection remains cc4"
  assert_contains "${output}" "--worktree ${FIXTURE_WORKTREES}/cc4" "dry-run launcher command uses clean cc4 worktree"
  cleanup_fixture
}

test_select_cc_skips_live_db_and_allows_stale_db() {
  log_test "select-cc-worker uses DB process liveness"

  setup_fixture
  enable_runtime_checks
  setup_fake_tmux ""
  init_gateway_db
  insert_task_row live-cc3 cc3 "" running "$$"

  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" select-cc-worker --verbose 2>&1)" || exit_code="$?"
  if [[ "${exit_code}" -eq 0 ]]; then
    pass "select-cc-worker skips live DB row and exits zero"
  else
    fail "select-cc-worker should skip live DB row: ${output}"
  fi
  assert_contains "${output}" "worker=cc3" "verbose includes cc3 availability"
  assert_contains "${output}" "reasons=busy-db-active" "live DB row blocks cc3"
  assert_contains "${output}" "Selected CC worker: cc4" "live DB row advances to cc4"
  cleanup_fixture

  setup_fixture
  enable_runtime_checks
  setup_fake_tmux ""
  init_gateway_db
  insert_task_row stale-cc3 cc3 "" running 999999

  exit_code=0
  output="$("${MY_WORKFLOWS_SH}" select-cc-worker --verbose 2>&1)" || exit_code="$?"
  if [[ "${exit_code}" -eq 0 ]]; then
    pass "select-cc-worker does not treat stale DB row as live busy"
  else
    fail "select-cc-worker should accept stale DB row for review: ${output}"
  fi
  assert_contains "${output}" "worker=cc3" "verbose includes stale cc3 availability"
  assert_contains "${output}" "available=true" "stale DB row remains selectable"
  assert_contains "${output}" "reasons=db-stale-review" "stale DB row is review reason"
  assert_contains "${output}" "Selected CC worker: cc3" "stale DB row does not skip cc3"
  cleanup_fixture
}

test_select_workers_skip_family_tmux_sessions() {
  log_test "select workers skip family tmux sessions"

  setup_fixture
  enable_runtime_checks
  setup_fake_tmux $'claude-cc3-demo\ncodex-cx3-demo'

  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" select-cc-worker --verbose 2>&1)" || exit_code="$?"
  if [[ "${exit_code}" -eq 0 ]]; then
    pass "select-cc-worker skips existing Claude session"
  else
    fail "select-cc-worker should skip existing Claude session: ${output}"
  fi
  assert_contains "${output}" "worker=cc3" "cc verbose includes cc3"
  assert_contains "${output}" "reasons=busy-tmux-session" "Claude session blocks cc3"
  assert_contains "${output}" "Selected CC worker: cc4" "cc session advances to cc4"

  exit_code=0
  output="$("${MY_WORKFLOWS_SH}" select-cx-worker --verbose 2>&1)" || exit_code="$?"
  if [[ "${exit_code}" -eq 0 ]]; then
    pass "select-cx-worker skips existing Codex session"
  else
    fail "select-cx-worker should skip existing Codex session: ${output}"
  fi
  assert_contains "${output}" "worker=cx3" "cx verbose includes cx3"
  assert_contains "${output}" "reasons=busy-tmux-session" "Codex session blocks cx3"
  assert_contains "${output}" "Selected CX repair worker: cx4" "cx session advances to cx4"
  cleanup_fixture
}

test_select_cx_skips_db_active_and_pane_cwd() {
  log_test "select-cx-worker uses DB and pane cwd busy checks"

  setup_fixture
  enable_runtime_checks
  local panes
  panes="$(printf 'codex-free\t%s/cx4\tbash\t%s\n' "${FIXTURE_WORKTREES}" "$$")"
  setup_fake_tmux "" "${panes}"
  init_gateway_db
  insert_task_row live-cx3 cx3 "" running "$$"

  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" select-cx-worker --verbose 2>&1)" || exit_code="$?"
  if [[ "${exit_code}" -eq 0 ]]; then
    pass "select-cx-worker skips DB-active and pane-cwd workers"
  else
    fail "select-cx-worker should skip busy cx workers: ${output}"
  fi
  assert_contains "${output}" "worker=cx3" "verbose includes cx3 availability"
  assert_contains "${output}" "reasons=busy-db-active" "live DB row blocks cx3"
  assert_contains "${output}" "worker=cx4" "verbose includes cx4 availability"
  assert_contains "${output}" "busy-pane-cwd" "pane cwd blocks cx4"
  assert_contains "${output}" "Selected CX repair worker: cx5" "busy cx3/cx4 advances to cx5"
  cleanup_fixture
}

test_status_uses_availability_helper_for_full_worker_pool() {
  log_test "status uses shared availability for full worker pool"

  setup_fixture
  enable_runtime_checks
  printf 'dirty\n' > "${FIXTURE_WORKTREES}/cc6/dirty.txt"
  local panes
  panes="$(printf 'codex-cx2-fixed\t%s/cx2\tbash\t%s\n' "${FIXTURE_WORKTREES}" "$$")"
  setup_fake_tmux $'claude-cc7-demo' "${panes}"
  init_gateway_db
  insert_task_row stale-cc8 cc8 "" running 999999

  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" status 2>&1)" || exit_code="$?"
  if [[ "${exit_code}" -eq 0 ]]; then
    pass "status exits zero with shared availability"
  else
    fail "status should exit zero: ${output}"
  fi
  assert_contains "${output}" "cc10" "status covers cc10"
  assert_contains "${output}" "cc6 (dirty)" "status reports dirty reason"
  assert_contains "${output}" "cc7 (busy-tmux-session)" "status reports tmux session reason"
  assert_contains "${output}" "cc8 (db-stale-review)" "status reports stale DB review reason"
  assert_contains "${output}" "cx2 (busy-pane-cwd)" "status detects fixed cx2 pane cwd occupancy"
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

  local repair_handoff="${FIXTURE_TG_DIR}/.omx/codex-handoffs/cx3-fixdemo-repair.md"
  assert_file_contains "${repair_handoff}" "Codex Repair Handoff" "repair writes cx handoff"
  assert_file_contains "${FIXTURE_LAUNCH_LOG}" "launch_codex_worker_terminal.sh|worktree=${FIXTURE_WORKTREES}/cx3|task=cx3-fixdemo-repair" "repair launches cx3 Codex"
  if [[ -d "${FIXTURE_TG_DIR}/.omx/codex-task-queue/logs" ]]; then
    pass "repair prepares codex task queue log directory"
  else
    fail "repair should prepare codex task queue log directory"
  fi
  if [[ ! -e "${FIXTURE_TG_DIR}/plans/cx3-fixdemo-repair.md" ]]; then
    pass "repair does not write prompt to plans"
  else
    fail "repair should not write prompt to plans"
  fi
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
  assert_file_contains "${FIXTURE_LAUNCH_LOG}" "prompt=${FIXTURE_TG_DIR}/.omx/codex-handoffs/cx2-reviewdemo-review.md" "review writes prompt to codex handoffs"

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

test_observe_group_dry_run_writes_result_and_skips_paste() {
  log_test "observe-group dry-run writes result and skips paste"

  setup_fixture
  setup_fake_tmux $'claude-cc3-observe-demo\nclaude-cc4-observe-demo-docs'

  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" observe-group \
    --task observe-demo \
    --workers cc3,cc4 \
    --target-pane cx2:0.0 \
    --dry-run 2>&1)" || exit_code="$?"

  local report
  report="$(observe_report_path observe-demo)"

  if [[ "${exit_code}" -eq 0 ]]; then
    pass "observe-group dry-run exits zero"
  else
    fail "observe-group dry-run should exit zero: ${output}"
  fi
  assert_contains "${output}" "${report}" "dry-run prints report path"
  assert_file_contains "${report}" "Task slug: \`observe-demo\`" "report records task slug"
  assert_file_contains "${report}" "Observed workers: \`cc3,cc4\`" "report records all workers"
  assert_file_contains "${report}" "Target cx2 pane: \`cx2:0.0\`" "report records target pane"
  assert_file_contains "${report}" "Matched tmux session: \`claude-cc4-observe-demo-docs\`" "report matches task-prefixed lane session"
  assert_file_not_contains "${FAKE_TMUX_LOG}" "paste-buffer" "dry-run does not paste to tmux"
  cleanup_fixture
}

test_observe_group_rejects_invalid_workers() {
  log_test "observe-group rejects invalid workers"

  setup_fixture
  setup_fake_tmux ""

  local workers output exit_code
  for workers in cc2 cc11 cx3; do
    exit_code=0
    output="$("${MY_WORKFLOWS_SH}" observe-group --task invalid-demo --workers "${workers}" --dry-run 2>&1)" || exit_code="$?"
    if [[ "${exit_code}" -ne 0 ]]; then
      pass "rejects ${workers}"
    else
      fail "observe-group should reject ${workers}"
    fi
    if [[ "${workers}" == "cc2" ]]; then
      assert_contains "${output}" "reserved as observer" "invalid ${workers} error is explicit"
    else
      assert_contains "${output}" "Observed worker must be one of cc3-cc10" "invalid ${workers} error is explicit"
    fi
  done

  cleanup_fixture
}

test_observe_group_marks_missing_worktree_and_session() {
  log_test "observe-group marks missing worktree/session"

  setup_fixture
  rm -rf "${FIXTURE_WORKTREES}/cc6"
  setup_fake_tmux $'claude-cc3-missing-demo'

  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" observe-group \
    --task missing-demo \
    --workers cc3,cc4,cc6 \
    --target-pane cx2:0.0 \
    --dry-run 2>&1)" || exit_code="$?"

  if [[ "${exit_code}" -eq 0 ]]; then
    pass "observe-group handles missing resources without crashing"
  else
    fail "observe-group should not crash on missing resources: ${output}"
  fi

  local report
  report="$(observe_report_path missing-demo)"
  assert_file_contains "${report}" "Worker \`cc4\`" "report includes missing-session worker"
  assert_file_contains "${report}" "State: \`missing-session\`" "report marks missing session"
  assert_file_contains "${report}" "missing worktree" "report marks missing worktree"
  assert_file_contains "${report}" "人工确认 blocker" "report recommends blocker confirmation"
  cleanup_fixture
}

test_observe_group_marks_dirty_worker_ready_for_review() {
  log_test "observe-group marks completed dirty worker for review"

  setup_fixture
  setup_fake_tmux $'claude-cc3-review-demo'
  printf 'change\n' > "${FIXTURE_WORKTREES}/cc3/change.txt"

  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" observe-group \
    --task review-demo \
    --workers cc3 \
    --target-pane cx2:0.0 \
    --dry-run 2>&1)" || exit_code="$?"

  if [[ "${exit_code}" -eq 0 ]]; then
    pass "observe-group dirty review case exits zero"
  else
    fail "observe-group dirty review case should exit zero: ${output}"
  fi

  local report
  report="$(observe_report_path review-demo)"
  assert_file_contains "${report}" "State: \`dirty-needs-review\`" "dirty completed worker needs review"
  assert_file_contains "${report}" "Recommendation: \`进入 review\`" "dirty completed worker recommends review"
  cleanup_fixture
}

test_observe_group_marks_failed_worker_blocked() {
  log_test "observe-group marks failed worker blocked"

  setup_fixture
  setup_fake_tmux $'claude-cc3-failed-demo'
  export MY_WORKFLOWS_FAKE_TMUX_CAPTURE='● Summary
Error: Exit code 1
Verification failed'
  printf 'change\n' > "${FIXTURE_WORKTREES}/cc3/change.txt"

  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" observe-group \
    --task failed-demo \
    --workers cc3 \
    --target-pane cx2:0.0 \
    --dry-run 2>&1)" || exit_code="$?"

  if [[ "${exit_code}" -eq 0 ]]; then
    pass "observe-group failed worker case exits zero"
  else
    fail "observe-group failed worker case should exit zero: ${output}"
  fi

  local report
  report="$(observe_report_path failed-demo)"
  assert_file_contains "${report}" "State: \`blocked\`" "failed worker is blocked"
  assert_file_contains "${report}" "Recommendation: \`要求 worker 修复\`" "failed worker recommends repair"
  cleanup_fixture
}

test_observe_group_non_dry_run_uses_tmux_arguments() {
  log_test "observe-group non-dry-run uses tmux arguments"

  setup_fixture
  setup_fake_tmux $'claude-cc3-send-demo'

  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" observe-group \
    --task send-demo \
    --workers cc3 \
    --target-pane cx2:0.0 2>&1)" || exit_code="$?"

  if [[ "${exit_code}" -eq 0 ]]; then
    pass "observe-group non-dry-run exits zero"
  else
    fail "observe-group non-dry-run should exit zero: ${output}"
  fi

  assert_file_contains "${FAKE_TMUX_LOG}" "load-buffer" "non-dry-run loads tmux buffer"
  assert_file_contains "${FAKE_TMUX_LOG}" "paste-buffer -t cx2:0.0" "non-dry-run pastes to target pane"
  assert_file_contains "${FAKE_TMUX_LOG}" "send-keys -t cx2:0.0 Enter" "non-dry-run sends Enter to target pane"
  cleanup_fixture
}

test_observe_group_sends_summary_for_long_report() {
  log_test "observe-group sends summary for long report"

  setup_fixture
  setup_fake_tmux $'claude-cc3-summary-demo'
  export MY_WORKFLOWS_OBSERVER_REPORT_SEND_LIMIT_BYTES=1

  local output
  local exit_code=0
  output="$("${MY_WORKFLOWS_SH}" observe-group \
    --task summary-demo \
    --workers cc3 \
    --target-pane cx2:0.0 2>&1)" || exit_code="$?"

  if [[ "${exit_code}" -eq 0 ]]; then
    pass "observe-group summary send exits zero"
  else
    fail "observe-group summary send should exit zero: ${output}"
  fi

  local summary="${FIXTURE_TG_DIR}/.omx/observers/summary-demo.summary.md"
  local report
  report="$(observe_report_path summary-demo)"
  assert_file_contains "${FAKE_TMUX_LOG}" "load-buffer ${summary}" "long report loads summary buffer"
  assert_file_contains "${summary}" "report: ${report}" "summary points to full report"
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
  test_select_cc_skips_live_db_and_allows_stale_db
  test_select_workers_skip_family_tmux_sessions
  test_select_cx_skips_db_active_and_pane_cwd
  test_status_uses_availability_helper_for_full_worker_pool
  test_select_cx_rejects_cc_worker
  test_repair_writes_handoff_and_launches_codex
  test_review_launches_cx2_only
  test_integrate_writes_candidate
  test_observe_group_dry_run_writes_result_and_skips_paste
  test_observe_group_rejects_invalid_workers
  test_observe_group_marks_missing_worktree_and_session
  test_observe_group_marks_dirty_worker_ready_for_review
  test_observe_group_marks_failed_worker_blocked
  test_observe_group_non_dry_run_uses_tmux_arguments
  test_observe_group_sends_summary_for_long_report
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
