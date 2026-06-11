#!/usr/bin/env bash
# my_workflows.sh - cx1/cx2/worker 状态机和编排脚本
set -euo pipefail

# 配置
MY_AGENTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="${MY_WORKFLOWS_SCRIPTS_DIR:-${MY_AGENTS_DIR}/scripts}"
TG_GATEWAY_DIR="${MY_WORKFLOWS_TG_GATEWAY_DIR:-/home/zhanxp/projects/tg-agent-gateway}"
TG_GATEWAY_WORKTREES="${MY_WORKFLOWS_TG_GATEWAY_WORKTREES:-/home/zhanxp/worktrees/tg-agent-gateway}"

# 状态文件目录
STATE_DIR=""
OMX_DIR=""
CLAUDE_HANDOFFS_DIR=""
CODEX_HANDOFFS_DIR=""
LAUNCHERS_DIR=""
OBSERVERS_DIR=""
INTEGRATION_CANDIDATES_DIR=""
CODEX_TASK_QUEUE_LOGS_DIR=""

# 默认值
DEFAULT_CC_WORKERS=("cc3" "cc4" "cc5" "cc6" "cc7" "cc8" "cc9" "cc10")
DEFAULT_CX_REPAIR_WORKERS=("cx3" "cx4" "cx5")
DEFAULT_OBSERVER_WORKER="cc2"
DEFAULT_CX_REVIEW_WORKER="cx2"

# 运行时状态
CURRENT_PHASE=""
CURRENT_TASK=""
SELECTED_CC_WORKER=""
SELECTED_CX_REPAIR_WORKER=""
SELECTED_CX_REVIEW_WORKER=""
HAS_OBSERVER=0
DRY_RUN=0
VERBOSE=0
INPUT_PROMPT_FILE=""
IGNORE_RUNTIME_BUSY="${MY_WORKFLOWS_IGNORE_RUNTIME_BUSY:-0}"
OBSERVE_WORKERS_CSV=""
OBSERVE_TARGET_PANE="cx2:0.0"
OBSERVE_WORKER_LIST=()
OBSERVER_REPORT_SEND_LIMIT_BYTES="${MY_WORKFLOWS_OBSERVER_REPORT_SEND_LIMIT_BYTES:-12000}"

usage() {
  cat <<'EOF_USAGE'
Usage:
  my_workflows.sh <command> [options]

Commands:
  plan                运行 cx1 规划模式
  orchestrate         运行 cx2 编排模式
  repair              运行 cx repair 模式
  review              运行 cx2 review 模式
  integrate           运行 master 集成模式
  observe-group       生成 cc2 当前任务组观察报告并发送给 cx2
  select-cc-worker      选择可用的 cc worker
  select-cx-worker    选择可用的 cx repair worker
  status              显示当前工作流状态
  help                显示此帮助

Options:
  --state-dir <dir>   状态目录 (default: $TG_GATEWAY_DIR/.omx)
  --task <slug>       任务 slug
  --worker <name>     指定 worker (ccN/cxN)
  --workers <list>    observe-group 显式 worker 列表，例如 cc3,cc4
  --target-pane <pane> observe-group 发送目标 pane (default: cx2:0.0)
  --prompt-file <path> handoff prompt 文件
  --dry-run          只打印命令不执行
  --verbose          详细输出
  -h, --help         显示此帮助
EOF_USAGE
}

log() {
  printf '[\033[32m*\033[0m] %s\n' "$*" >&2
}

log_phase() {
  printf '\n\033[1;34m=== %s ===\033[0m\n\n' "$*" >&2
}

vlog() {
  if [[ "${VERBOSE:-0}" -eq 1 ]]; then
    printf '[\033[36m.\033[0m] %s\n' "$*" >&2
  fi
}

warn() {
  printf '[\033[33mWARN\033[0m] %s\n' "$*" >&2
}

die() {
  printf '[\033[31mERROR\033[0m] %s\n' "$*" >&2
  exit 1
}

init_directories() {
  local command="${1:-}"
  if [[ -z "${STATE_DIR:-}" ]]; then
    STATE_DIR="${TG_GATEWAY_DIR}/.omx"
  fi
  OMX_DIR="${STATE_DIR}"
  CLAUDE_HANDOFFS_DIR="${OMX_DIR}/claude-handoffs"
  CODEX_HANDOFFS_DIR="${OMX_DIR}/codex-handoffs"
  LAUNCHERS_DIR="${OMX_DIR}/codex-launchers"
  OBSERVERS_DIR="${OMX_DIR}/observers"
  INTEGRATION_CANDIDATES_DIR="${OMX_DIR}/integration-candidates"
  CODEX_TASK_QUEUE_LOGS_DIR="${OMX_DIR}/codex-task-queue/logs"

  case "${command}" in
    help|plan|select-cc-worker|select-cx-worker|status)
      return 0
      ;;
  esac

  for dir in "${OMX_DIR}" "${CLAUDE_HANDOFFS_DIR}" "${CODEX_HANDOFFS_DIR}" "${LAUNCHERS_DIR}" "${OBSERVERS_DIR}" "${INTEGRATION_CANDIDATES_DIR}" "${CODEX_TASK_QUEUE_LOGS_DIR}"; do
    if [[ ! -d "${dir}" ]]; then
      mkdir -p "${dir}"
    fi
  done
}

array_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "${item}" == "${needle}" ]] && return 0
  done
  return 1
}

join_by_comma() {
  local joined=""
  local item
  for item in "$@"; do
    [[ -n "${item}" ]] || continue
    if [[ -n "${joined}" ]]; then
      joined+=","
    fi
    joined+="${item}"
  done
  printf '%s\n' "${joined}"
}

is_cc_worker_name() {
  [[ "$1" =~ ^cc[0-9]+$ ]]
}

is_cx_worker_name() {
  [[ "$1" =~ ^cx[0-9]+$ ]]
}

is_cx_repair_worker_name() {
  array_contains "$1" "${DEFAULT_CX_REPAIR_WORKERS[@]}"
}

validate_requested_cc_worker() {
  local requested_worker="$1"
  [[ -z "${requested_worker}" ]] && return 0
  is_cc_worker_name "${requested_worker}" || die "Requested worker must be a cc worker: ${requested_worker}"
}

validate_requested_cx_repair_worker() {
  local requested_worker="$1"
  [[ -z "${requested_worker}" ]] && return 0
  is_cx_worker_name "${requested_worker}" || die "Requested worker must be a cx worker: ${requested_worker}"
  is_cx_repair_worker_name "${requested_worker}" || die "Requested CX repair worker must be one of: ${DEFAULT_CX_REPAIR_WORKERS[*]}"
}

validate_requested_cx_review_worker() {
  local requested_worker="$1"
  [[ -z "${requested_worker}" ]] && return 0
  is_cx_worker_name "${requested_worker}" || die "Requested review worker must be a cx worker: ${requested_worker}"
  [[ "${requested_worker}" == "${DEFAULT_CX_REVIEW_WORKER}" ]] || die "Review worker is fixed to ${DEFAULT_CX_REVIEW_WORKER}"
}

require_task_slug() {
  local phase="$1"
  local task_slug="${CURRENT_TASK:-}"
  [[ -n "${task_slug}" ]] || die "--task is required for ${phase}"
  [[ "${task_slug}" =~ ^[A-Za-z0-9._-]+$ ]] || die "--task must contain only letters, numbers, '.', '_' or '-'"
  printf '%s\n' "${task_slug}"
}

require_prompt_file() {
  local phase="$1"
  [[ -n "${INPUT_PROMPT_FILE:-}" ]] || die "--prompt-file is required for ${phase}"
  [[ -f "${INPUT_PROMPT_FILE}" ]] || die "Prompt file not found: ${INPUT_PROMPT_FILE}"
  printf '%s\n' "${INPUT_PROMPT_FILE}"
}

validate_observe_target_pane() {
  local target_pane="$1"
  [[ -n "${target_pane}" ]] || die "--target-pane must not be empty"
  [[ "${target_pane}" =~ ^[A-Za-z0-9_.:%-]+$ ]] || die "--target-pane contains unsupported characters: ${target_pane}"
}

parse_observe_workers() {
  local workers_csv="$1"
  [[ -n "${workers_csv}" ]] || die "--workers is required for observe-group"

  OBSERVE_WORKER_LIST=()
  local -a raw_workers=()
  local raw_worker worker
  IFS=',' read -r -a raw_workers <<< "${workers_csv}"
  for raw_worker in "${raw_workers[@]}"; do
    worker="${raw_worker//[[:space:]]/}"
    [[ -n "${worker}" ]] || die "--workers contains an empty worker entry"
    if [[ "${worker}" == "${DEFAULT_OBSERVER_WORKER}" ]]; then
      die "${DEFAULT_OBSERVER_WORKER} is reserved as observer and cannot be observed"
    fi
    is_cc_worker_name "${worker}" || die "Observed worker must be one of cc3-cc10: ${worker}"
    array_contains "${worker}" "${DEFAULT_CC_WORKERS[@]}" || die "Observed worker must be one of cc3-cc10: ${worker}"
    OBSERVE_WORKER_LIST+=("${worker}")
  done

  [[ "${#OBSERVE_WORKER_LIST[@]}" -gt 0 ]] || die "--workers is required for observe-group"
}

join_observe_workers() {
  local joined=""
  local worker
  for worker in "${OBSERVE_WORKER_LIST[@]}"; do
    if [[ -n "${joined}" ]]; then
      joined+=","
    fi
    joined+="${worker}"
  done
  printf '%s\n' "${joined}"
}

observe_expected_session() {
  local worker="$1"
  local task_slug="$2"
  printf 'claude-%s-%s\n' "${worker}" "${task_slug}"
}

observe_matching_session() {
  local worker="$1"
  local task_slug="$2"
  local expected
  expected="$(observe_expected_session "${worker}" "${task_slug}")"

  local session
  while IFS= read -r session; do
    if [[ "${session}" == "${expected}" ]]; then
      printf '%s\n' "${session}"
      return 0
    fi
    case "${session}" in
      "${expected}-"*)
        printf '%s\n' "${session}"
        return 0
        ;;
    esac
  done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)

  printf '%s\n' "${expected}"
}

observe_tmux_session_exists() {
  local session="$1"
  tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -Fxq -- "${session}"
}

observe_tmux_value() {
  local target="$1"
  local format="$2"
  tmux display-message -p -t "${target}" "${format}" 2>/dev/null || true
}

observe_tmux_tail() {
  local target="$1"
  tmux capture-pane -pt "${target}" -S -80 2>/dev/null || true
}

observe_worker_completed() {
  local tail_text="$1"
  printf '%s\n' "${tail_text}" |
    grep -Eqi '^●[[:space:]].*(最终|总结|Summary|Changed Files|PASS|---)|^●[[:space:]]*(Summary|Changed Files|PASS|---)'
}

observe_worker_blocked() {
  local tail_text="$1"
  printf '%s\n' "${tail_text}" |
    grep -Eqi '(^|[[:space:]])(FAIL|failed|failure|blocker|blocked|ERROR|失败|报错)([[:space:]:。,.]|$)'
}

observe_worker_success_evidence() {
  local tail_text="$1"
  printf '%s\n' "${tail_text}" |
    grep -Eqi 'All tests passed|Failed:[[:space:]]*0|0 failed|PASS|通过'
}

observe_worker_state() {
  local worktree="$1"
  local session_exists="$2"
  local git_status="$3"
  local tmux_tail="$4"

  if [[ ! -d "${worktree}" ]]; then
    printf 'missing-session\n'
    return 0
  fi

  if [[ "${session_exists}" -ne 1 ]]; then
    printf 'missing-session\n'
    return 0
  fi

  if observe_worker_blocked "${tmux_tail}" && ! observe_worker_success_evidence "${tmux_tail}"; then
    printf 'blocked\n'
    return 0
  fi

  if observe_worker_completed "${tmux_tail}"; then
    if [[ -n "${git_status}" ]]; then
      printf 'dirty-needs-review\n'
    else
      printf 'ready-for-review\n'
    fi
    return 0
  fi

  printf 'running\n'
}

observe_worker_suggestion() {
  local state="$1"
  case "${state}" in
    running)
      printf '继续等待\n'
      ;;
    ready-for-review|dirty-needs-review)
      printf '进入 review\n'
      ;;
    blocked)
      printf '要求 worker 修复\n'
      ;;
    missing-session|*)
      printf '人工确认 blocker\n'
      ;;
  esac
}

observe_overall_suggestion() {
  local has_running=0
  local has_review=0
  local has_blocker=0
  local state
  for state in "$@"; do
    case "${state}" in
      running) has_running=1 ;;
      ready-for-review|dirty-needs-review) has_review=1 ;;
      blocked|missing-session) has_blocker=1 ;;
    esac
  done

  if [[ "${has_blocker}" -eq 1 ]]; then
    printf '人工确认 blocker\n'
  elif [[ "${has_running}" -eq 1 ]]; then
    printf '继续等待\n'
  elif [[ "${has_review}" -eq 1 ]]; then
    printf '进入 review\n'
  else
    printf '人工确认 blocker\n'
  fi
}

render_observe_group_report() {
  local task_slug="$1"
  local target_pane="$2"
  local generated_at="$3"
  local workers_csv
  workers_csv="$(join_observe_workers)"
  local -a states=()

  printf '# cc2 Group Observer Report\n\n'
  printf -- '- Task slug: `%s`\n' "${task_slug}"
  printf -- '- Generated at: `%s`\n' "${generated_at}"
  printf -- '- Observed workers: `%s`\n' "${workers_csv}"
  printf -- '- Target cx2 pane: `%s`\n\n' "${target_pane}"

  local worker
  for worker in "${OBSERVE_WORKER_LIST[@]}"; do
    local worktree="${TG_GATEWAY_WORKTREES}/${worker}"
    local expected_session
    expected_session="$(observe_expected_session "${worker}" "${task_slug}")"
    local session
    session="$(observe_matching_session "${worker}" "${task_slug}")"
    local session_exists=0
    if observe_tmux_session_exists "${session}"; then
      session_exists=1
    fi

    local pane_target="${session}:0.0"
    local pane_command=""
    local pane_path=""
    local tmux_tail=""
    if [[ "${session_exists}" -eq 1 ]]; then
      pane_command="$(observe_tmux_value "${pane_target}" '#{pane_current_command}')"
      pane_path="$(observe_tmux_value "${pane_target}" '#{pane_current_path}')"
      tmux_tail="$(observe_tmux_tail "${pane_target}")"
    fi

    local git_status=""
    local diff_stat=""
    if [[ -d "${worktree}" ]]; then
      git_status="$(git -C "${worktree}" status --short 2>/dev/null || true)"
      diff_stat="$(git -C "${worktree}" diff --stat 2>/dev/null || true)"
    fi

    local state
    state="$(observe_worker_state "${worktree}" "${session_exists}" "${git_status}" "${tmux_tail}")"
    states+=("${state}")

    printf '## Worker `%s`\n\n' "${worker}"
    printf -- '- Worktree: `%s`\n' "${worktree}"
    printf -- '- Expected tmux session: `%s` or `%s-*`\n' "${expected_session}" "${expected_session}"
    printf -- '- Matched tmux session: `%s`\n' "${session}"
    printf -- '- Tmux session: `%s`\n' "$([[ "${session_exists}" -eq 1 ]] && printf present || printf missing)"
    printf -- '- Tmux pane command: `%s`\n' "${pane_command:-missing}"
    printf -- '- Tmux pane path: `%s`\n' "${pane_path:-missing}"
    printf -- '- State: `%s`\n' "${state}"
    printf -- '- Recommendation: `%s`\n\n' "$(observe_worker_suggestion "${state}")"

    printf '### Git status\n\n```text\n'
    if [[ -d "${worktree}" ]]; then
      printf '%s\n' "${git_status:-clean}"
    else
      printf 'missing worktree\n'
    fi
    printf '```\n\n'

    printf '### Diff stat\n\n```text\n'
    if [[ -d "${worktree}" ]]; then
      printf '%s\n' "${diff_stat:-none}"
    else
      printf 'missing worktree\n'
    fi
    printf '```\n\n'

    printf '### Recent tmux output\n\n```text\n'
    if [[ "${session_exists}" -eq 1 ]]; then
      printf '%s\n' "${tmux_tail:-no output}"
    else
      printf 'missing-session\n'
    fi
    printf '```\n\n'
  done

  printf '## cx2 Recommendation\n\n'
  printf '%s\n' "$(observe_overall_suggestion "${states[@]}")"
}

send_observe_group_report() {
  local target_pane="$1"
  local report_file="$2"
  local summary_file="$3"

  local send_file="${report_file}"
  local report_bytes
  report_bytes="$(wc -c < "${report_file}")"
  if (( report_bytes > OBSERVER_REPORT_SEND_LIMIT_BYTES )); then
    send_file="${summary_file}"
  fi

  tmux load-buffer "${send_file}"
  tmux paste-buffer -t "${target_pane}"
  tmux send-keys -t "${target_pane}" Enter
}

write_prompt_file() {
  local prompt_file="$1"
  local prompt_content="$2"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN: Would write handoff prompt to ${prompt_file}"
    return 0
  fi

  mkdir -p "$(dirname "${prompt_file}")"
  printf '%s\n' "${prompt_content}" > "${prompt_file}"
  log "Wrote handoff prompt: ${prompt_file}"
}

is_git_worktree_clean() {
  local worktree="$1"
  if [[ ! -d "${worktree}" ]]; then
    return 1
  fi
  local status
  status="$(git -C "${worktree}" status --short 2>/dev/null)" || return 1
  [[ -z "${status}" ]]
}

AV_WORKER=""
AV_FAMILY=""
AV_AVAILABLE="false"
AV_DECISION="skip"
AV_REASONS_TEXT="none"
AV_WORKTREE=""
AV_DIRTY_COUNT=0
AV_TMUX_SESSIONS_TEXT="none"
AV_PANE_CWD_HITS_TEXT="none"
AV_DB_ACTIVE_ROWS=0
AV_DB_STALE_ROWS=0

worker_family() {
  local worker="$1"
  if is_cc_worker_name "${worker}"; then
    printf 'cc\n'
  elif is_cx_worker_name "${worker}"; then
    printf 'cx\n'
  else
    printf 'unknown\n'
  fi
}

worker_tmux_prefix() {
  local family="$1"
  case "${family}" in
    cc) printf 'claude\n' ;;
    cx) printf 'codex\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

process_is_alive() {
  local pid="$1"
  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
  [[ "${pid}" -gt 0 ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

git_dirty_count() {
  local worktree="$1"
  local status
  status="$(git -C "${worktree}" status --short 2>/dev/null)" || {
    printf '1\n'
    return 0
  }
  if [[ -z "${status}" ]]; then
    printf '0\n'
  else
    printf '%s\n' "${status}" | grep -c '^'
  fi
}

collect_worker_tmux_sessions() {
  local worker="$1"
  local family="$2"
  if [[ "${IGNORE_RUNTIME_BUSY}" == "1" ]]; then
    return 0
  fi

  local prefix
  prefix="$(worker_tmux_prefix "${family}")"
  [[ "${prefix}" != "unknown" ]] || return 0

  local session
  while IFS= read -r session; do
    [[ -n "${session}" ]] || continue
    case "${session}" in
      "${prefix}-${worker}-"*)
        printf '%s\n' "${session}"
        ;;
    esac
  done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)
}

collect_worker_pane_cwd_hits() {
  local worktree="$1"
  if [[ "${IGNORE_RUNTIME_BUSY}" == "1" ]]; then
    return 0
  fi

  local tmux_format
  tmux_format=$'#{session_name}\t#{pane_current_path}\t#{pane_current_command}\t#{pane_pid}'
  local session pane_path pane_command pane_pid
  while IFS=$'\t' read -r session pane_path pane_command pane_pid; do
    [[ -n "${pane_path}" ]] || continue
    case "${pane_path}" in
      "${worktree}"|"${worktree}/"*)
        if [[ -n "${pane_pid:-}" ]] && [[ "${pane_pid}" =~ ^[0-9]+$ ]] && ! process_is_alive "${pane_pid}"; then
          continue
        fi
        printf '%s:%s:%s:%s\n' "${session:-unknown}" "${pane_path}" "${pane_command:-unknown}" "${pane_pid:-unknown}"
        ;;
    esac
  done < <(tmux list-panes -a -F "${tmux_format}" 2>/dev/null || true)
}

collect_worker_db_counts() {
  local worker="$1"
  if [[ "${IGNORE_RUNTIME_BUSY}" == "1" ]]; then
    printf '0 0\n'
    return 0
  fi

  local db_path="${TG_GATEWAY_DIR}/data/gateway.sqlite"
  if [[ ! -f "${db_path}" ]] || ! command -v sqlite3 >/dev/null 2>&1; then
    printf '0 0\n'
    return 0
  fi

  local active=0
  local stale=0
  local id status process_id
  while IFS=$'\t' read -r id status process_id; do
    [[ -n "${id:-}" ]] || continue
    if [[ -z "${process_id:-}" || "${process_id}" == "0" ]]; then
      active=$((active + 1))
    elif process_is_alive "${process_id}"; then
      active=$((active + 1))
    else
      stale=$((stale + 1))
    fi
  done < <(
    sqlite3 -separator $'\t' "${db_path}" \
      "SELECT id, status, COALESCE(process_id, '') FROM tasks WHERE status IN ('running', 'queued', 'planned', 'pending', 'processing') AND (worker = '${worker}' OR recommended_agent = '${worker}') ORDER BY created_at DESC LIMIT 50;" \
      2>/dev/null || true
  )

  printf '%s %s\n' "${active}" "${stale}"
}

collect_worker_availability() {
  local worker="$1"
  AV_WORKER="${worker}"
  AV_FAMILY="$(worker_family "${worker}")"
  AV_AVAILABLE="false"
  AV_DECISION="skip"
  AV_WORKTREE="${TG_GATEWAY_WORKTREES}/${worker}"
  AV_DIRTY_COUNT=0
  AV_TMUX_SESSIONS_TEXT="none"
  AV_PANE_CWD_HITS_TEXT="none"
  AV_DB_ACTIVE_ROWS=0
  AV_DB_STALE_ROWS=0

  local -a reasons=()
  local has_blocking_reason=0

  if [[ "${AV_FAMILY}" == "unknown" ]]; then
    reasons+=("invalid-worker")
    has_blocking_reason=1
  fi

  if [[ ! -d "${AV_WORKTREE}" ]]; then
    reasons+=("missing-worktree")
    has_blocking_reason=1
  else
    AV_DIRTY_COUNT="$(git_dirty_count "${AV_WORKTREE}")"
    if [[ "${AV_DIRTY_COUNT}" -gt 0 ]]; then
      reasons+=("dirty")
      has_blocking_reason=1
    fi
  fi

  local tmux_sessions
  tmux_sessions="$(collect_worker_tmux_sessions "${worker}" "${AV_FAMILY}")"
  if [[ -n "${tmux_sessions}" ]]; then
    AV_TMUX_SESSIONS_TEXT="$(printf '%s\n' "${tmux_sessions}" | paste -sd, -)"
    reasons+=("busy-tmux-session")
    has_blocking_reason=1
  fi

  if [[ -d "${AV_WORKTREE}" ]]; then
    local pane_hits
    pane_hits="$(collect_worker_pane_cwd_hits "${AV_WORKTREE}")"
    if [[ -n "${pane_hits}" ]]; then
      AV_PANE_CWD_HITS_TEXT="$(printf '%s\n' "${pane_hits}" | paste -sd, -)"
      reasons+=("busy-pane-cwd")
      has_blocking_reason=1
    fi
  fi

  local db_counts
  db_counts="$(collect_worker_db_counts "${worker}")"
  read -r AV_DB_ACTIVE_ROWS AV_DB_STALE_ROWS <<< "${db_counts}"
  if [[ "${AV_DB_ACTIVE_ROWS}" -gt 0 ]]; then
    reasons+=("busy-db-active")
    has_blocking_reason=1
  fi
  if [[ "${AV_DB_STALE_ROWS}" -gt 0 ]]; then
    reasons+=("db-stale-review")
  fi

  if [[ "${#reasons[@]}" -eq 0 ]]; then
    AV_REASONS_TEXT="none"
  else
    AV_REASONS_TEXT="$(join_by_comma "${reasons[@]}")"
  fi

  if [[ "${has_blocking_reason}" -eq 0 ]]; then
    AV_AVAILABLE="true"
    if [[ "${AV_DB_STALE_ROWS}" -gt 0 ]]; then
      AV_DECISION="available-db-stale-review"
    else
      AV_DECISION="available"
    fi
  fi
}

render_worker_availability() {
  printf 'worker=%s family=%s available=%s decision=%s reasons=%s worktree=%s dirtyCount=%s tmuxSessions=%s paneCwdHits=%s dbActiveRows=%s dbStaleRows=%s\n' \
    "${AV_WORKER}" \
    "${AV_FAMILY}" \
    "${AV_AVAILABLE}" \
    "${AV_DECISION}" \
    "${AV_REASONS_TEXT}" \
    "${AV_WORKTREE}" \
    "${AV_DIRTY_COUNT}" \
    "${AV_TMUX_SESSIONS_TEXT}" \
    "${AV_PANE_CWD_HITS_TEXT}" \
    "${AV_DB_ACTIVE_ROWS}" \
    "${AV_DB_STALE_ROWS}"
}

is_cc_worker_available() {
  local worker="$1"
  collect_worker_availability "${worker}"
  [[ "${AV_FAMILY}" == "cc" && "${AV_AVAILABLE}" == "true" ]]
}

is_cx_worker_available() {
  local worker="$1"
  collect_worker_availability "${worker}"
  [[ "${AV_FAMILY}" == "cx" && "${AV_AVAILABLE}" == "true" ]]
}

select_available_cc_worker() {
  local requested_worker="${1:-}"
  if [[ -n "${requested_worker}" ]]; then
    if ! is_cc_worker_name "${requested_worker}"; then
      die "Requested worker must be a cc worker: ${requested_worker}"
    fi
    collect_worker_availability "${requested_worker}"
    if [[ "${VERBOSE}" -eq 1 ]]; then
      render_worker_availability >&2
    fi
    if [[ "${AV_AVAILABLE}" == "true" ]]; then
      printf '%s\n' "${requested_worker}"
      return 0
    else
      warn "Requested worker ${requested_worker} is not available: ${AV_REASONS_TEXT}"
      return 1
    fi
  fi

  for worker in "${DEFAULT_CC_WORKERS[@]}"; do
    collect_worker_availability "${worker}"
    if [[ "${VERBOSE}" -eq 1 ]]; then
      render_worker_availability >&2
    fi
    if [[ "${AV_AVAILABLE}" == "true" ]]; then
      printf '%s\n' "${worker}"
      return 0
    fi
  done

  return 1
}

select_available_cx_repair_worker() {
  local requested_worker="${1:-}"
  if [[ -n "${requested_worker}" ]]; then
    if ! is_cx_worker_name "${requested_worker}"; then
      die "Requested worker must be a cx worker: ${requested_worker}"
    fi
    if ! is_cx_repair_worker_name "${requested_worker}"; then
      die "Requested CX repair worker must be one of: ${DEFAULT_CX_REPAIR_WORKERS[*]}"
    fi
    collect_worker_availability "${requested_worker}"
    if [[ "${VERBOSE}" -eq 1 ]]; then
      render_worker_availability >&2
    fi
    if [[ "${AV_AVAILABLE}" == "true" ]]; then
      printf '%s\n' "${requested_worker}"
      return 0
    else
      warn "Requested CX worker ${requested_worker} is not available: ${AV_REASONS_TEXT}"
      return 1
    fi
  fi

  for worker in "${DEFAULT_CX_REPAIR_WORKERS[@]}"; do
    collect_worker_availability "${worker}"
    if [[ "${VERBOSE}" -eq 1 ]]; then
      render_worker_availability >&2
    fi
    if [[ "${AV_AVAILABLE}" == "true" ]]; then
      printf '%s\n' "${worker}"
      return 0
    fi
  done

  return 1
}

select_available_cx_review_worker() {
  local requested_worker="${1:-${DEFAULT_CX_REVIEW_WORKER}}"
  if [[ -z "${requested_worker}" ]]; then
    requested_worker="${DEFAULT_CX_REVIEW_WORKER}"
  fi
  if ! is_cx_worker_name "${requested_worker}"; then
    die "Requested review worker must be a cx worker: ${requested_worker}"
  fi
  if [[ "${requested_worker}" != "${DEFAULT_CX_REVIEW_WORKER}" ]]; then
    die "Review worker is fixed to ${DEFAULT_CX_REVIEW_WORKER}"
  fi
  collect_worker_availability "${requested_worker}"
  if [[ "${VERBOSE}" -eq 1 ]]; then
    render_worker_availability >&2
  fi
  if [[ "${AV_AVAILABLE}" == "true" ]]; then
    printf '%s\n' "${requested_worker}"
    return 0
  fi
  warn "Review worker ${requested_worker} is not available: ${AV_REASONS_TEXT}"
  return 1
}

is_observer_available() {
  is_cc_worker_available "${DEFAULT_OBSERVER_WORKER}"
}

select_observer_worker() {
  if is_observer_available; then
    printf '%s\n' "${DEFAULT_OBSERVER_WORKER}"
    return 0
  fi
  return 1
}

write_handoff_prompt() {
  local task_slug="$1"
  local prompt_content="$2"
  local prompt_file="${CLAUDE_HANDOFFS_DIR}/${task_slug}.md"

  write_prompt_file "${prompt_file}" "${prompt_content}"
  printf '%s\n' "${prompt_file}"
}

render_cc_handoff_prompt() {
  local task_slug="$1"
  local worker="$2"
  local source_prompt_file="$3"
  local worktree="${TG_GATEWAY_WORKTREES}/${worker}"

  cat <<EOF
# Claude Worker Handoff

Task: ${task_slug}
Worker: ${worker}
Worktree: ${worktree}
Source prompt: ${source_prompt_file}

## Execution Contract

- Work only inside ${worktree}.
- Do not edit master or unrelated worktrees.
- Keep the diff within the requested scope.
- Run the verification commands requested in the source prompt.
- Report changed files, verification evidence, blockers, and residual risk.

## Source Prompt

$(cat "${source_prompt_file}")
EOF
}

render_observer_prompt() {
  local task_slug="$1"
  local observer="$2"
  local implementation_workers="$3"
  local source_prompt_file="$4"
  local result_file="${OBSERVERS_DIR}/${task_slug}.result.md"

  cat <<EOF
# Read-Only Observer Handoff

Task: ${task_slug}
Observer: ${observer}
Implementation workers: ${implementation_workers}
Observer result file: ${result_file}
Target cx2 pane: ${OBSERVE_TARGET_PANE}
Source prompt: ${source_prompt_file}

Observe the current task group without editing files. One cc2 observer covers
all listed implementation workers; do not scan historical worker sessions.

For each implementation worker, inspect:
- Worktree: ${TG_GATEWAY_WORKTREES}/<worker>
- Tmux session: claude-<worker>-${task_slug} or claude-<worker>-${task_slug}-*
- Git status and diff stat
- Recent tmux pane output

Generate the group observer report with:

\`\`\`bash
${BASH_SOURCE[0]} observe-group --task ${task_slug} --workers ${implementation_workers} --target-pane ${OBSERVE_TARGET_PANE}
\`\`\`

The report must be written to ${result_file} and sent to cx2. It must include
worker status, diff summary, verification evidence, stalls/failures/blockers,
result path, and one of these states for each worker: ready-for-review,
running, blocked, missing-session, dirty-needs-review.

## Source Prompt

$(cat "${source_prompt_file}")
EOF
}

render_cx_repair_prompt() {
  local task_slug="$1"
  local worker="$2"
  local source_prompt_file="$3"
  local worktree="${TG_GATEWAY_WORKTREES}/${worker}"

  cat <<EOF
# Codex Repair Handoff

Task: ${task_slug}
Repair worker: ${worker}
Worktree: ${worktree}
Source prompt: ${source_prompt_file}

## Repair Contract

- Work only inside ${worktree}.
- Repair the final candidate described in the source prompt.
- Do not change command semantics, callbacks, data contracts, permissions, or
  unrelated files unless the source prompt explicitly requires it.
- Run the requested verification and report evidence.

## Source Prompt

$(cat "${source_prompt_file}")
EOF
}

render_cx_review_prompt() {
  local task_slug="$1"
  local worker="$2"
  local source_prompt_file="$3"
  local worktree="${TG_GATEWAY_WORKTREES}/${worker}"

  cat <<EOF
# cx2 Review Handoff

Task: ${task_slug}
Review worker: ${worker}
Worktree: ${worktree}
Source prompt: ${source_prompt_file}

Review the completed worker diff read-only against the plan and verification
evidence. Output pass/fail, blocking findings with file references, verification
evidence, residual risks, and the recommended master integration candidate.
Do not implement, merge, commit, or push.

## Source Prompt

$(cat "${source_prompt_file}")
EOF
}

render_integration_candidate() {
  local task_slug="$1"
  local source_prompt_file="$2"

  cat <<EOF
# Master Integration Candidate

Task: ${task_slug}
Source prompt: ${source_prompt_file}

This file records the cx2-approved integration input for master. Apply only the
review-passed candidate described below, run final verification, refresh runtime
when applicable, and push only when the workflow or user explicitly requests it.

## Source Prompt

$(cat "${source_prompt_file}")
EOF
}

launch_cc_worker() {
  local worker="$1"
  local task_slug="$2"
  local prompt_file="$3"
  local worktree="${TG_GATEWAY_WORKTREES}/${worker}"
  local launcher_task_slug="${worker}-${task_slug}"
  local launcher="${SCRIPTS_DIR}/launch_claude_worker_terminal.sh"

  log "Launching Claude worker ${worker} for task ${task_slug}"

  [[ -f "${launcher}" ]] || die "Claude launcher not found: ${launcher}"

  local launcher_cmd=(
    "${launcher}"
    --worktree "${worktree}"
    --task-slug "${launcher_task_slug}"
    --prompt-file "${prompt_file}"
    --title "${worker}"
  )

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    launcher_cmd+=(--dry-run)
  fi

  if [[ "${VERBOSE}" -eq 1 ]]; then
    launcher_cmd+=(--verbose)
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN: Would execute:"
    printf '  '
    printf '%q' "${launcher_cmd[0]}"
    local arg
    for arg in "${launcher_cmd[@]:1}"; do
      printf ' %q' "${arg}"
    done
    printf '\n'
  else
    "${launcher_cmd[@]}"
  fi
}

launch_cx_worker() {
  local worker="$1"
  local task_slug="$2"
  local prompt_file="$3"
  local worktree="${TG_GATEWAY_WORKTREES}/${worker}"
  local model="${4:-${OMX_DEFAULT_CX_MODEL:-gpt-5.3-codex-spark}}"
  local reasoning_effort="${5:-${OMX_DEFAULT_CX_REASONING_EFFORT:-xhigh}}"
  local launcher_task_slug="${worker}-${task_slug}"
  local launcher="${SCRIPTS_DIR}/launch_codex_worker_terminal.sh"

  log "Launching Codex worker ${worker} for task ${task_slug}"

  [[ -f "${launcher}" ]] || die "Codex launcher not found: ${launcher}"

  local launcher_cmd=(
    "${launcher}"
    --worktree "${worktree}"
    --task-slug "${launcher_task_slug}"
    --prompt-file "${prompt_file}"
    --title "${worker}"
    --model "${model}"
    --reasoning-effort "${reasoning_effort}"
  )

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    launcher_cmd+=(--dry-run)
  fi

  if [[ "${VERBOSE}" -eq 1 ]]; then
    launcher_cmd+=(--verbose)
  fi

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN: Would execute:"
    printf '  '
    printf '%q' "${launcher_cmd[0]}"
    local arg
    for arg in "${launcher_cmd[@]:1}"; do
      printf ' %q' "${arg}"
    done
    printf '\n'
  else
    "${launcher_cmd[@]}"
  fi
}

cmd_select_cc_worker() {
  log_phase "选择 CC Worker"

  local requested_worker="${1:-}"
  validate_requested_cc_worker "${requested_worker}"
  local worker

  worker="$(select_available_cc_worker "${requested_worker}")" || {
    die "No available CC worker found"
  }

  log "Selected CC worker: ${worker}"
  printf '%s\n' "${worker}"
}

cmd_select_cx_worker() {
  log_phase "选择 CX Repair Worker"

  local requested_worker="${1:-}"
  validate_requested_cx_repair_worker "${requested_worker}"
  local worker

  worker="$(select_available_cx_repair_worker "${requested_worker}")" || {
    die "No available CX repair worker found"
  }

  log "Selected CX repair worker: ${worker}"
  printf '%s\n' "${worker}"
}

cmd_plan() {
  log_phase "CX1 规划模式"
  local task_slug
  task_slug="$(require_task_slug "plan")"
  log "Planning phase for ${task_slug}: keep cx1 plan-only and write the decision-complete handoff prompt before orchestrate."
}

cmd_orchestrate() {
  log_phase "CX2 编排模式"

  local task_slug
  task_slug="$(require_task_slug "orchestrate")"
  local source_prompt_file
  source_prompt_file="$(require_prompt_file "orchestrate")"

  validate_requested_cc_worker "${SELECTED_CC_WORKER:-}"
  local worker
  worker="$(select_available_cc_worker "${SELECTED_CC_WORKER:-}")" || {
    die "No available CC worker for orchestration"
  }
  SELECTED_CC_WORKER="${worker}"
  log "Selected CC worker: ${SELECTED_CC_WORKER}"

  local handoff_file="${CLAUDE_HANDOFFS_DIR}/${SELECTED_CC_WORKER}-${task_slug}.md"
  local handoff_prompt
  handoff_prompt="$(render_cc_handoff_prompt "${task_slug}" "${SELECTED_CC_WORKER}" "${source_prompt_file}")"
  write_prompt_file "${handoff_file}" "${handoff_prompt}"
  launch_cc_worker "${SELECTED_CC_WORKER}" "${task_slug}" "${handoff_file}"

  local observer_worker=""
  if is_observer_available; then
    observer_worker="${DEFAULT_OBSERVER_WORKER}"
    HAS_OBSERVER=1
    log "Observer worker available: ${observer_worker}"
    local observer_prompt_file="${CLAUDE_HANDOFFS_DIR}/${observer_worker}-${task_slug}-observer.md"
    local observer_prompt
    observer_prompt="$(render_observer_prompt "${task_slug}" "${observer_worker}" "${SELECTED_CC_WORKER}" "${source_prompt_file}")"
    write_prompt_file "${observer_prompt_file}" "${observer_prompt}"
    launch_cc_worker "${observer_worker}" "${task_slug}-observer" "${observer_prompt_file}"
  else
    warn "Observer worker ${DEFAULT_OBSERVER_WORKER} not available"
  fi

  log "Orchestration ready:"
  log "  CC Worker: ${SELECTED_CC_WORKER}"
  if [[ "${HAS_OBSERVER}" -eq 1 ]]; then
    log "  Observer: ${observer_worker}"
  fi
  log "  Task: ${task_slug}"
}

cmd_repair() {
  log_phase "CX Repair 模式"

  local task_slug
  task_slug="$(require_task_slug "repair")"
  local source_prompt_file
  source_prompt_file="$(require_prompt_file "repair")"

  validate_requested_cx_repair_worker "${SELECTED_CX_REPAIR_WORKER:-}"
  local worker
  worker="$(select_available_cx_repair_worker "${SELECTED_CX_REPAIR_WORKER:-}")" || {
    die "No available CX repair worker"
  }
  SELECTED_CX_REPAIR_WORKER="${worker}"
  log "Selected CX repair worker: ${SELECTED_CX_REPAIR_WORKER}"

  local handoff_file="${CODEX_HANDOFFS_DIR}/${SELECTED_CX_REPAIR_WORKER}-${task_slug}-repair.md"
  local handoff_prompt
  handoff_prompt="$(render_cx_repair_prompt "${task_slug}" "${SELECTED_CX_REPAIR_WORKER}" "${source_prompt_file}")"
  write_prompt_file "${handoff_file}" "${handoff_prompt}"
  launch_cx_worker "${SELECTED_CX_REPAIR_WORKER}" "${task_slug}-repair" "${handoff_file}"

  log "Repair launched for task ${task_slug}"
}

cmd_review() {
  log_phase "CX2 Review 模式"

  local task_slug
  task_slug="$(require_task_slug "review")"
  local source_prompt_file
  source_prompt_file="$(require_prompt_file "review")"

  validate_requested_cx_review_worker "${SELECTED_CX_REVIEW_WORKER:-}"
  local worker
  worker="$(select_available_cx_review_worker "${SELECTED_CX_REVIEW_WORKER:-}")" || {
    die "No available CX review worker"
  }
  SELECTED_CX_REVIEW_WORKER="${worker}"
  log "Selected CX review worker: ${SELECTED_CX_REVIEW_WORKER}"

  local handoff_file="${CODEX_HANDOFFS_DIR}/${SELECTED_CX_REVIEW_WORKER}-${task_slug}-review.md"
  local handoff_prompt
  handoff_prompt="$(render_cx_review_prompt "${task_slug}" "${SELECTED_CX_REVIEW_WORKER}" "${source_prompt_file}")"
  write_prompt_file "${handoff_file}" "${handoff_prompt}"
  launch_cx_worker "${SELECTED_CX_REVIEW_WORKER}" "${task_slug}-review" "${handoff_file}"

  log "Review launched for task ${task_slug}"
}

cmd_integrate() {
  log_phase "Master 集成模式"

  local task_slug
  task_slug="$(require_task_slug "integrate")"
  local source_prompt_file
  source_prompt_file="$(require_prompt_file "integrate")"

  local candidate_file="${INTEGRATION_CANDIDATES_DIR}/${task_slug}.md"
  local candidate_prompt
  candidate_prompt="$(render_integration_candidate "${task_slug}" "${source_prompt_file}")"
  write_prompt_file "${candidate_file}" "${candidate_prompt}"

  log "Integration candidate ready: ${candidate_file}"
  printf '%s\n' "${candidate_file}"
}

cmd_observe_group() {
  log_phase "CC2 当前任务组观察报告"

  local task_slug
  task_slug="$(require_task_slug "observe-group")"
  parse_observe_workers "${OBSERVE_WORKERS_CSV}"
  validate_observe_target_pane "${OBSERVE_TARGET_PANE}"

  local generated_at
  generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  local report_file="${OBSERVERS_DIR}/${task_slug}.result.md"
  local summary_file="${OBSERVERS_DIR}/${task_slug}.summary.md"

  render_observe_group_report "${task_slug}" "${OBSERVE_TARGET_PANE}" "${generated_at}" > "${report_file}"
  {
    printf '[observe-group] %s\n' "${task_slug}"
    printf 'workers: %s\n' "$(join_observe_workers)"
    printf 'report: %s\n' "${report_file}"
    printf 'target: %s\n' "${OBSERVE_TARGET_PANE}"
  } > "${summary_file}"

  log "Wrote observer report: ${report_file}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN: skipped tmux paste to ${OBSERVE_TARGET_PANE}"
    printf '%s\n' "${report_file}"
    return 0
  fi

  if send_observe_group_report "${OBSERVE_TARGET_PANE}" "${report_file}" "${summary_file}"; then
    log "Sent observer report to ${OBSERVE_TARGET_PANE}"
  else
    warn "Failed to send observer report to ${OBSERVE_TARGET_PANE}; report remains at ${report_file}"
  fi

  printf '%s\n' "${report_file}"
}

cmd_status() {
  log_phase "工作流状态"

  log "TG Gateway worktree availability:"
  local -a workers=("${DEFAULT_OBSERVER_WORKER}" "${DEFAULT_CC_WORKERS[@]}" "${DEFAULT_CX_REVIEW_WORKER}" "${DEFAULT_CX_REPAIR_WORKERS[@]}")
  local worker
  for worker in "${workers[@]}"; do
    collect_worker_availability "${worker}"
    local status_symbol="✓"
    if [[ "${AV_AVAILABLE}" != "true" ]]; then
      status_symbol="✗"
    fi

    printf '  %s %s' "${status_symbol}" "${worker}"
    if [[ "${AV_REASONS_TEXT}" != "none" ]]; then
      printf ' (%s)' "${AV_REASONS_TEXT}"
    fi
    printf '\n'
  done

  printf '\n'
  log "Active tmux sessions:"
  tmux list-sessions 2>/dev/null | sed 's/^/  /' || printf '  (none)\n'
}

main() {
  local command=""
  local requested_worker=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      plan|orchestrate|repair|review|integrate|observe-group|select-cc-worker|select-cx-worker|status|help)
        command="$1"
        shift
        ;;
      --state-dir)
        [[ "$#" -ge 2 ]] || die "--state-dir requires a value"
        STATE_DIR="$2"
        shift 2
        ;;
      --task)
        [[ "$#" -ge 2 ]] || die "--task requires a value"
        CURRENT_TASK="$2"
        shift 2
        ;;
      --worker)
        [[ "$#" -ge 2 ]] || die "--worker requires a value"
        requested_worker="$2"
        shift 2
        ;;
      --workers)
        [[ "$#" -ge 2 ]] || die "--workers requires a value"
        OBSERVE_WORKERS_CSV="$2"
        shift 2
        ;;
      --target-pane)
        [[ "$#" -ge 2 ]] || die "--target-pane requires a value"
        OBSERVE_TARGET_PANE="$2"
        shift 2
        ;;
      --prompt-file)
        [[ "$#" -ge 2 ]] || die "--prompt-file requires a value"
        INPUT_PROMPT_FILE="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --verbose)
        VERBOSE=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "Unknown argument: $1"
        ;;
    esac
  done

  if [[ -z "${command}" ]]; then
    usage >&2
    die "Command is required"
  fi

  init_directories "${command}"

  case "${command}" in
    plan)
      cmd_plan
      ;;
    orchestrate)
      SELECTED_CC_WORKER="${requested_worker}"
      cmd_orchestrate
      ;;
    repair)
      SELECTED_CX_REPAIR_WORKER="${requested_worker}"
      cmd_repair
      ;;
    review)
      SELECTED_CX_REVIEW_WORKER="${requested_worker}"
      cmd_review
      ;;
    integrate)
      cmd_integrate
      ;;
    observe-group)
      cmd_observe_group
      ;;
    select-cc-worker)
      cmd_select_cc_worker "${requested_worker}"
      ;;
    select-cx-worker)
      cmd_select_cx_worker "${requested_worker}"
      ;;
    status)
      cmd_status
      ;;
    help)
      usage
      ;;
    *)
      usage >&2
      die "Unknown command: ${command}"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
