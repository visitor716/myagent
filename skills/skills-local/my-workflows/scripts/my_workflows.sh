#!/usr/bin/env bash
# my_workflows.sh - cx1/cx2/worker 状态机和编排脚本
set -euo pipefail

# 配置
MY_AGENTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="${MY_AGENTS_DIR}/scripts"
TG_GATEWAY_DIR="/home/zhanxp/projects/tg-agent-gateway"
TG_GATEWAY_WORKTREES="/home/zhanxp/worktrees/tg-agent-gateway"

# 状态文件目录
STATE_DIR=""
OMX_DIR=""
CLAUDE_HANDOFFS_DIR=""
LAUNCHERS_DIR=""
OBSERVERS_DIR=""

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
  select-cc-worker      选择可用的 cc worker
  select-cx-worker    选择可用的 cx repair worker
  status              显示当前工作流状态
  help                显示此帮助

Options:
  --state-dir <dir>   状态目录 (default: $TG_GATEWAY_DIR/.omx)
  --task <slug>       任务 slug
  --worker <name>     指定 worker (ccN/cxN)
  --prompt-file <path> handoff prompt 文件
  --dry-run          只打印命令不执行
  --verbose          详细输出
  -h, --help         显示此帮助
EOF_USAGE
}

log() {
  printf '[\033[32m*\033[0m] %s\n' "$*"
}

log_phase() {
  printf '\n\033[1;34m=== %s ===\033[0m\n\n' "$*"
}

vlog() {
  if [[ "${VERBOSE:-0}" -eq 1 ]]; then
    printf '[\033[36m.\033[0m] %s\n' "$*"
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
  if [[ -z "${STATE_DIR:-}" ]]; then
    STATE_DIR="${TG_GATEWAY_DIR}/.omx"
  fi
  OMX_DIR="${STATE_DIR}"
  CLAUDE_HANDOFFS_DIR="${OMX_DIR}/claude-handoffs"
  LAUNCHERS_DIR="${OMX_DIR}/codex-launchers"
  OBSERVERS_DIR="${OMX_DIR}/observers"

  for dir in "${OMX_DIR}" "${CLAUDE_HANDOFFS_DIR}" "${LAUNCHERS_DIR}" "${OBSERVERS_DIR}"; do
    if [[ ! -d "${dir}" ]]; then
      mkdir -p "${dir}"
    fi
  done
}

is_git_worktree_clean() {
  local worktree="$1"
  if [[ ! -d "${worktree}" ]]; then
    return 1
  fi
  local status
  status="$(git -C "${worktree}" status --short)"
  [[ -z "${status}" ]]
}

has_tmux_session() {
  local pattern="$1"
  tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -q "${pattern}"
}

has_active_db_task() {
  local worker="$1"
  local db_path="${TG_GATEWAY_DIR}/data/gateway.sqlite"
  if [[ ! -f "${db_path}" ]]; then
    return 1
  fi
  sqlite3 "${db_path}" \
    "SELECT 1 FROM tasks WHERE status IN ('running', 'queued', 'planned', 'pending', 'processing') AND (worker = '${worker}' OR recommended_agent = '${worker}') LIMIT 1;" \
    2>/dev/null | grep -q 1
}

is_cc_worker_available() {
  local worker="$1"
  local worktree="${TG_GATEWAY_WORKTREES}/${worker}"

  if [[ ! -d "${worktree}" ]]; then
    vlog "Worker ${worker} missing worktree: ${worktree}"
    return 1
  fi

  if ! is_git_worktree_clean "${worktree}"; then
    vlog "Worker ${worker} worktree is dirty"
    return 1
  fi

  if has_tmux_session "^claude-${worker}-"; then
    vlog "Worker ${worker} has active tmux session"
    return 1
  fi

  if has_active_db_task "${worker}"; then
    vlog "Worker ${worker} has active DB task"
    return 1
  fi

  return 0
}

is_cx_worker_available() {
  local worker="$1"
  local worktree="${TG_GATEWAY_WORKTREES}/${worker}"

  if [[ ! -d "${worktree}" ]]; then
    vlog "CX Worker ${worker} missing worktree: ${worktree}"
    return 1
  fi

  if ! is_git_worktree_clean "${worktree}"; then
    vlog "CX Worker ${worker} worktree is dirty"
    return 1
  fi

  if has_tmux_session "^codex-${worker}-"; then
    vlog "CX Worker ${worker} has active tmux session"
    return 1
  fi

  return 0
}

select_available_cc_worker() {
  local requested_worker="${1:-}"
  if [[ -n "${requested_worker}" ]]; then
    if is_cc_worker_available "${requested_worker}"; then
      printf '%s\n' "${requested_worker}"
      return 0
    else
      warn "Requested worker ${requested_worker} is not available"
      return 1
    fi
  fi

  for worker in "${DEFAULT_CC_WORKERS[@]}"; do
    if is_cc_worker_available "${worker}"; then
      printf '%s\n' "${worker}"
      return 0
    fi
  done

  return 1
}

select_available_cx_repair_worker() {
  local requested_worker="${1:-}"
  if [[ -n "${requested_worker}" ]]; then
    if is_cx_worker_available "${requested_worker}"; then
      printf '%s\n' "${requested_worker}"
      return 0
    else
      warn "Requested CX worker ${requested_worker} is not available"
      return 1
    fi
  fi

  for worker in "${DEFAULT_CX_REPAIR_WORKERS[@]}"; do
    if is_cx_worker_available "${worker}"; then
      printf '%s\n' "${worker}"
      return 0
    fi
  done

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

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "DRY-RUN: Would write handoff prompt to ${prompt_file}"
    printf '%s\n' "${prompt_content}"
  else
    printf '%s\n' "${prompt_content}" > "${prompt_file}"
    log "Wrote handoff prompt: ${prompt_file}"
  fi

  printf '%s\n' "${prompt_file}"
}

launch_cc_worker() {
  local worker="$1"
  local task_slug="$2"
  local prompt_file="$3"
  local worktree="${TG_GATEWAY_WORKTREES}/${worker}"

  log "Launching Claude worker ${worker} for task ${task_slug}"

  local launcher_cmd=(
    "${SCRIPTS_DIR}/launch_claude_worker_terminal.sh"
    --worktree "${worktree}"
    --task-slug "${task_slug}"
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
    printf '  %q ' "${launcher_cmd[@]}"
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

  log "Launching Codex worker ${worker} for task ${task_slug}"

  local launcher_cmd=(
    "${SCRIPTS_DIR}/launch_codex_worker_terminal.sh"
    --worktree "${worktree}"
    --task-slug "${task_slug}"
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
    printf '  %q ' "${launcher_cmd[@]}"
    printf '\n'
  else
    "${launcher_cmd[@]}"
  fi
}

cmd_select_cc_worker() {
  log_phase "选择 CC Worker"

  local requested_worker="${1:-}"
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
  local worker

  worker="$(select_available_cx_repair_worker "${requested_worker}")" || {
    die "No available CX repair worker found"
  }

  log "Selected CX repair worker: ${worker}"
  printf '%s\n' "${worker}"
}

cmd_plan() {
  log_phase "CX1 规划模式"
  log "This is the planning phase. Use Codex cx1 for planning tasks."
  log "TODO: Implement cx1 planning orchestration"
}

cmd_orchestrate() {
  log_phase "CX2 编排模式"

  local task_slug="${CURRENT_TASK:-}"
  if [[ -z "${task_slug}" ]]; then
    die "--task is required for orchestrate"
  fi

  local worker
  worker="$(select_available_cc_worker "${SELECTED_CC_WORKER:-}")" || {
    die "No available CC worker for orchestration"
  }
  SELECTED_CC_WORKER="${worker}"
  log "Selected CC worker: ${SELECTED_CC_WORKER}"

  local observer_worker=""
  if is_observer_available; then
    observer_worker="${DEFAULT_OBSERVER_WORKER}"
    HAS_OBSERVER=1
    log "Observer worker available: ${observer_worker}"
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

  local task_slug="${CURRENT_TASK:-}"
  if [[ -z "${task_slug}" ]]; then
    die "--task is required for repair"
  fi

  local worker
  worker="$(select_available_cx_repair_worker "${SELECTED_CX_REPAIR_WORKER:-}")" || {
    die "No available CX repair worker"
  }
  SELECTED_CX_REPAIR_WORKER="${worker}"
  log "Selected CX repair worker: ${SELECTED_CX_REPAIR_WORKER}"

  log "Repair mode ready for task ${task_slug}"
}

cmd_review() {
  log_phase "CX2 Review 模式"
  log "Review phase: cx2 reviews worker results"
  log "TODO: Implement cx2 review orchestration"
}

cmd_integrate() {
  log_phase "Master 集成模式"
  log "Integration phase: apply accepted changes to master"
  log "TODO: Implement master integration orchestration"
}

cmd_status() {
  log_phase "工作流状态"

  log "TG Gateway worktree availability:"
  for worker in cc2 cc3 cc4 cc5 cx2 cx3 cx4 cx5; do
    local worktree="${TG_GATEWAY_WORKTREES}/${worker}"
    local status_symbol="✓"
    local details=()

    if [[ ! -d "${worktree}" ]]; then
      status_symbol="✗"
      details+=("missing")
    else
      if ! is_git_worktree_clean "${worktree}"; then
        status_symbol="✗"
        details+=("dirty")
      fi
    fi

    if [[ "${worker}" =~ ^cc ]]; then
      if has_tmux_session "^claude-${worker}-"; then
        status_symbol="✗"
        details+=("busy-tmux")
      fi
      if has_active_db_task "${worker}"; then
        status_symbol="✗"
        details+=("busy-db")
      fi
    else
      if has_tmux_session "^codex-${worker}-"; then
        status_symbol="✗"
        details+=("busy-tmux")
      fi
    fi

    printf '  %s %s' "${status_symbol}" "${worker}"
    if [[ "${#details[@]}" -gt 0 ]]; then
      printf ' (%s)' "${details[*]}"
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
  local prompt_file=""

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      plan|orchestrate|repair|review|integrate|select-cc-worker|select-cx-worker|status|help)
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
      --prompt-file)
        [[ "$#" -ge 2 ]] || die "--prompt-file requires a value"
        prompt_file="$2"
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

  init_directories

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
      cmd_review
      ;;
    integrate)
      cmd_integrate
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
