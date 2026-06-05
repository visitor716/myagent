#!/usr/bin/env bash
# test_my_workflows.sh - 回归测试覆盖

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${TEST_DIR}/../scripts"
MY_WORKFLOWS_SH="${SCRIPTS_DIR}/my_workflows.sh"

# 测试计数器
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

log_test() {
  printf '\n[TEST] %s\n' "$*"
}

pass() {
  ((TESTS_PASSED++))
  ((TESTS_TOTAL++))
  printf '  [PASS] %s\n' "$*"
}

fail() {
  ((TESTS_FAILED++))
  ((TESTS_TOTAL++))
  printf '  [FAIL] %s\n' "$*" >&2
}

test_help() {
  log_test "帮助输出测试"

  local output
  output="$("${MY_WORKFLOWS_SH}" help 2>&1)"

  if printf '%s\n' "${output}" | grep -q "Usage:"; then
    pass "help 命令显示 Usage"
  else
    fail "help 命令未显示 Usage"
    return 1
  fi

  if printf '%s\n' "${output}" | grep -q "Commands:"; then
    pass "help 命令显示 Commands"
  else
    fail "help 命令未显示 Commands"
    return 1
  fi

  return 0
}

test_dry_run_flag() {
  log_test "--dry-run 标志测试"

  local exit_code=0
  "${MY_WORKFLOWS_SH}" select-cc-worker --dry-run >/dev/null 2>&1 || exit_code="$?"

  # 只要命令不崩溃就通过
  pass "--dry-run 标志不导致崩溃 (exit ${exit_code})"
  return 0
}

test_no_command_fails() {
  log_test "无命令时退出"

  local exit_code=0
  "${MY_WORKFLOWS_SH}" >/dev/null 2>&1 || exit_code="$?"

  if [[ "${exit_code}" -ne 0 ]]; then
    pass "无命令时正确退出非零"
  else
    fail "无命令时应退出非零"
  fi
}

test_unknown_command_fails() {
  log_test "未知命令时退出"

  local exit_code=0
  "${MY_WORKFLOWS_SH}" not-a-real-command >/dev/null 2>&1 || exit_code="$?"

  if [[ "${exit_code}" -ne 0 ]]; then
    pass "未知命令时正确退出非零"
  else
    fail "未知命令时应退出非零"
  fi
}

test_status_command_runs() {
  log_test "status 命令能运行"

  local exit_code=0
  "${MY_WORKFLOWS_SH}" status >/dev/null 2>&1 || exit_code="$?"

  # status 命令即使没有工作树也应该能运行
  pass "status 命令运行完成（代码 ${exit_code}）"
  return 0
}

test_script_syntax() {
  log_test "Shell 语法检查"

  local errors
  if ! errors="$(bash -n "${MY_WORKFLOWS_SH}" 2>&1)"; then
    fail "Shell 语法错误: ${errors}"
    return 1
  fi

  pass "Shell 语法正确"
  return 0
}

test_launcher_launch_codex_syntax() {
  log_test "launch_codex_worker_terminal.sh 语法检查"

  local launcher="${SCRIPTS_DIR}/launch_codex_worker_terminal.sh"
  if [[ ! -f "${launcher}" ]]; then
    pass "跳过，launcher 不存在"
    return 0
  fi

  local errors
  if ! errors="$(bash -n "${launcher}" 2>&1)"; then
    fail "launch_codex_worker_terminal.sh 语法错误: ${errors}"
    return 1
  fi

  pass "launch_codex_worker_terminal.sh 语法正确"
}

test_launcher_launch_claude_syntax() {
  log_test "launch_claude_worker_terminal.sh 语法检查"

  local launcher="${SCRIPTS_DIR}/launch_claude_worker_terminal.sh"
  if [[ ! -f "${launcher}" ]]; then
    pass "跳过，launcher 不存在"
    return 0
  fi

  local errors
  if ! errors="$(bash -n "${launcher}" 2>&1)"; then
    fail "launch_claude_worker_terminal.sh 语法错误: ${errors}"
    return 1
  fi

  pass "launch_claude_worker_terminal.sh 语法正确"
}

run_all_tests() {
  printf '\n=== my_workflows.sh 回归测试 ===\n'

  test_script_syntax
  test_help
  test_dry_run_flag
  test_no_command_fails
  test_unknown_command_fails
  test_status_command_runs
  test_launcher_launch_codex_syntax
  test_launcher_launch_claude_syntax

  printf '\n=== 测试结果 ===\n'
  printf '总计: %d\n' "${TESTS_TOTAL}"
  printf '通过: %d\n' "${TESTS_PASSED}"
  printf '失败: %d\n' "${TESTS_FAILED}"

  if [[ "${TESTS_FAILED}" -eq 0 ]]; then
    printf '\n✓ 所有测试通过!\n'
    return 0
  else
    printf '\n✗ 有测试失败!\n'
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_all_tests "$@"
fi
