#!/usr/bin/env bash
set -euo pipefail

WSL_DISTRO="${WSL_DISTRO_NAME:-}"
POWERSHELL_PATH="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

usage() {
  cat <<'USAGE'
Usage:
  tmux_process_windows.sh snapshot
  tmux_process_windows.sh summary
  tmux_process_windows.sh recent [target]
  tmux_process_windows.sh classify <target>
  tmux_process_windows.sh capture <target> [lines]
  tmux_process_windows.sh children <target>
  tmux_process_windows.sh new-codex-session <session> [cwd] [--no-open]
  tmux_process_windows.sh open-session <session>
  tmux_process_windows.sh send-text <target> <text> [--enter]
  tmux_process_windows.sh send-keys <target> <key...>
  tmux_process_windows.sh stop <target> [--kill-after <seconds> --yes]
  tmux_process_windows.sh kill-pane <target> --yes
  tmux_process_windows.sh kill-window <target> --yes
  tmux_process_windows.sh kill-session <target> --yes
USAGE
}

require_tmux() {
  if ! command -v tmux >/dev/null 2>&1; then
    echo "tmux is not installed or not on PATH" >&2
    exit 127
  fi
}

require_target() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    echo "missing tmux target" >&2
    usage >&2
    exit 2
  fi
}

require_yes() {
  local confirm="${1:-}"
  if [ "$confirm" != "--yes" ]; then
    echo "destructive action requires explicit --yes" >&2
    exit 2
  fi
}

require_directory() {
  local directory="$1"
  if [ ! -d "$directory" ]; then
    echo "directory does not exist: $directory" >&2
    exit 2
  fi
}

validate_session_name() {
  local session="$1"
  if ! printf '%s\n' "$session" | grep -Eq '^[A-Za-z0-9_.-]+$'; then
    echo "invalid session name: $session" >&2
    echo "allowed characters: letters, numbers, dot, underscore, hyphen" >&2
    exit 2
  fi
}

session_exists() {
  local session="$1"
  tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -Fxq -- "$session"
}

default_codex_session_cwd() {
  local session="$1"
  local tg_worktree="/home/zhanxp/worktrees/tg-agent-gateway/$session"
  if [ -d "$tg_worktree" ]; then
    printf '%s\n' "$tg_worktree"
    return 0
  fi

  return 1
}

get_wsl_distro() {
  if [ -n "$WSL_DISTRO" ]; then
    printf '%s\n' "$WSL_DISTRO"
    return 0
  fi

  if [ -f /etc/os-release ]; then
    local id
    id="$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' || true)"
    if [ -n "$id" ]; then
      printf '%s\n' "$id"
      return 0
    fi
  fi

  echo "Ubuntu"
}

find_windows_terminal() {
  local wt_paths=(
    "/mnt/c/Program Files/WindowsApps/Microsoft.WindowsTerminal_*/wt.exe"
    "/mnt/c/Users/$USER/AppData/Local/Microsoft/WindowsApps/wt.exe"
    "/mnt/c/Program Files/Windows Terminal/wt.exe"
  )

  for path in "${wt_paths[@]}"; do
    # Use compgen to handle globs
    if compgen -G "$path" >/dev/null 2>&1; then
      local found
      found="$(compgen -G "$path" 2>/dev/null | head -1)"
      if [ -n "$found" ] && [ -x "$found" ]; then
        printf '%s\n' "$found"
        return 0
      fi
    fi
  done

  return 1
}

open_wsl_terminal_window() {
  local session="$1"
  require_target "$session"

  local distro
  distro="$(get_wsl_distro)"

  echo "Opening terminal window for session: $session (distro: $distro)"

  # Try Windows Terminal first
  local wt_path
  if wt_path="$(find_windows_terminal)"; then
    echo "Using Windows Terminal: $wt_path"
    # Use a simple, reliable approach with a temporary script or direct invocation
    # Windows Terminal wt.exe expects its own argument format
    # Let's try a simpler approach first - just open a WSL window and let user attach
    local wt_winpath
    wt_winpath="$(wslpath -w "$wt_path" 2>/dev/null || echo "$wt_path")"
    "$POWERSHELL_PATH" -NoProfile -NonInteractive -Command \
      "Start-Process -FilePath '$wt_winpath' -ArgumentList 'wsl.exe', '-d', '$distro'" -WindowStyle Normal
    echo "Opened Windows Terminal window - please run: tmux attach -t '$session'"
    return 0
  fi

  # Fallback to PowerShell with ConHost
  echo "Windows Terminal not found, using PowerShell window"
  "$POWERSHELL_PATH" -NoProfile -NonInteractive -Command \
    "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoExit', '-Command', 'wsl.exe -d $distro'" -WindowStyle Normal
  echo "Opened PowerShell window - please run: tmux attach -t '$session'"
  return 0
}

pane_pid() {
  local target="$1"
  tmux display-message -p -t "$target" '#{pane_pid}'
}

pane_tty() {
  local target="$1"
  tmux display-message -p -t "$target" '#{pane_tty}'
}

tty_activity_age() {
  local tty="$1"
  local now stat_line access_time write_time last_activity

  if [ -z "$tty" ] || [ ! -e "$tty" ]; then
    echo "unknown"
    return 0
  fi

  now="$(date +%s)"
  stat_line="$(stat -c '%X %Y' "$tty" 2>/dev/null || true)"
  if [ -z "$stat_line" ]; then
    echo "unknown"
    return 0
  fi

  read -r access_time write_time <<<"$stat_line"
  if [ "$access_time" -ge "$write_time" ]; then
    last_activity="$access_time"
  else
    last_activity="$write_time"
  fi

  echo "$((now - last_activity))s"
}

summary() {
  if ! tmux list-sessions >/dev/null 2>&1; then
    echo "No tmux sessions."
    return 0
  fi

  echo "== Sessions =="
  tmux list-sessions -F 'session=#{session_name} windows=#{session_windows} attached=#{session_attached} created=#{session_created}'

  echo
  echo "== Windows =="
  tmux list-windows -a -F 'window=#{session_name}:#{window_index} name=#{window_name} panes=#{window_panes} active=#{window_active}'

  echo
  echo "== Panes =="
  tmux list-panes -a -F 'pane=#{session_name}:#{window_index}.#{pane_index} active=#{pane_active} dead=#{pane_dead} pid=#{pane_pid} tty=#{pane_tty} cmd=#{pane_current_command} cwd=#{pane_current_path} title=#{pane_title}'
}

recent_activity() {
  local target="${1:-}"
  local pane tty cmd cwd age

  if [ -n "$target" ]; then
    require_target "$target"
    tty="$(pane_tty "$target")"
    echo "pane=$target tty=$tty idle=$(tty_activity_age "$tty")"
    return 0
  fi

  tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}|#{pane_tty}|#{pane_current_command}|#{pane_current_path}' |
    while IFS='|' read -r pane tty cmd cwd; do
      age="$(tty_activity_age "$tty")"
      printf 'pane=%s idle=%s tty=%s cmd=%s cwd=%s\n' "$pane" "$age" "$tty" "$cmd" "$cwd"
    done
}

snapshot() {
  summary
  echo
  echo "== Recent TTY Activity =="
  recent_activity
  echo
  echo "== Relevant Processes =="
  pgrep -af 'tmux|codex|claude|node dist/index|cloudflared|monitor-webapp-url|cc-switch proxy|rescue-bot' || true
}

capture_pane() {
  local target="$1"
  local lines="${2:-120}"
  require_target "$target"
  tmux capture-pane -p -t "$target" -S "-$lines"
}

show_children() {
  local target="$1"
  require_target "$target"

  local pid
  pid="$(pane_pid "$target")"
  echo "pane_target=$target"
  echo "pane_pid=$pid"

  if command -v pstree >/dev/null 2>&1; then
    echo
    echo "== pstree =="
    pstree -ap "$pid" || true
  fi

  local pgid
  pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
  echo
  echo "== process group =="
  if [ -n "$pgid" ]; then
    ps -o pid,ppid,pgid,stat,etime,cmd --forest -g "$pgid" || true
  else
    ps -o pid,ppid,pgid,stat,etime,cmd -p "$pid" || true
  fi
}

new_codex_session() {
  local session="$1"
  local cwd=""
  local open_window="yes"

  # Parse arguments
  shift || true
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --no-open)
        open_window="no"
        shift
        ;;
      *)
        if [ -z "$cwd" ]; then
          cwd="$1"
        else
          echo "unknown argument: $1" >&2
          exit 2
        fi
        shift
        ;;
    esac
  done

  require_target "$session"
  validate_session_name "$session"

  if session_exists "$session"; then
    echo "tmux session already exists: $session" >&2
    echo "inspect it with: $0 capture $session:0.0 80" >&2
    if [ "$open_window" = "yes" ]; then
      echo "opening existing session window..."
      open_wsl_terminal_window "$session"
    fi
    exit 2
  fi

  if [ -z "$cwd" ]; then
    cwd="$(default_codex_session_cwd "$session" || true)"
  fi
  if [ -z "$cwd" ]; then
    echo "cwd is required when /home/zhanxp/worktrees/tg-agent-gateway/$session does not exist" >&2
    exit 2
  fi
  require_directory "$cwd"

  if ! command -v codex >/dev/null 2>&1; then
    echo "codex is not installed or not on PATH" >&2
    exit 127
  fi

  tmux new-session -d -s "$session" -n codex -c "$cwd" codex
  sleep 0.5
  echo "created codex session: $session"
  tmux list-panes -t "$session" -F 'pane=#{session_name}:#{window_index}.#{pane_index} active=#{pane_active} dead=#{pane_dead} pid=#{pane_pid} cmd=#{pane_current_command} cwd=#{pane_current_path} title=#{pane_title}'

  if [ "$open_window" = "yes" ]; then
    echo "opening terminal window..."
    open_wsl_terminal_window "$session"
  fi
}

classify_target() {
  local target="$1"
  require_target "$target"

  local output
  output="$(capture_pane "$target" 100 || true)"

  recent_activity "$target"
  echo
  echo "== Recent Output =="
  printf '%s\n' "$output"
  echo
  show_children "$target"
  echo
  echo "== Heuristics =="

  if printf '%s\n' "$output" | grep -Eiq 'Working|Synthesizing|esc to interrupt|Running|In progress|Compiling|Building|Testing'; then
    echo "active-signal: recent output looks like ongoing work"
  fi

  if printf '%s\n' "$output" | grep -Eiq 'DONE|Goal achieved|Changed Files|Verification|Token Usage|Worked for|Cooked for|Brewed for|Crunched for|new task|/clear'; then
    echo "completion-signal: recent output includes completion or idle prompt markers"
  fi

  case "$target" in
    tg-agent-gateway:*|tg-webapp-tunnel:*|tg-webapp-url-monitor:*|tg-rescue-bot:*|cc-switch-proxy:*|oa:*)
      echo "protected-signal: target matches a known protected service or project session"
      ;;
  esac

  echo "decision: use these signals as evidence, then choose inspect, send-text, stop, or exact kill action"
}

send_text() {
  local target="$1"
  local text="$2"
  local enter="${3:-}"
  require_target "$target"
  if [ -z "$text" ]; then
    echo "missing text" >&2
    exit 2
  fi

  tmux set-buffer -- "$text"
  tmux paste-buffer -t "$target"
  if [ "$enter" = "--enter" ]; then
    tmux send-keys -t "$target" Enter
  elif [ -n "$enter" ]; then
    echo "unknown option: $enter" >&2
    exit 2
  fi
}

stop_pane() {
  local target="$1"
  shift || true
  require_target "$target"

  local kill_after=""
  local confirmed="no"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --kill-after)
        kill_after="${2:-}"
        if [ -z "$kill_after" ]; then
          echo "missing seconds after --kill-after" >&2
          exit 2
        fi
        shift 2
        ;;
      --yes)
        confirmed="yes"
        shift
        ;;
      *)
        echo "unknown option: $1" >&2
        exit 2
        ;;
    esac
  done

  tmux send-keys -t "$target" C-c
  if [ -n "$kill_after" ]; then
    if [ "$confirmed" != "yes" ]; then
      echo "--kill-after requires --yes" >&2
      exit 2
    fi
    sleep "$kill_after"
    if tmux display-message -p -t "$target" '#{pane_id}' >/dev/null 2>&1; then
      tmux kill-pane -t "$target"
    fi
  fi
}

main() {
  require_tmux

  local action="${1:-summary}"
  shift || true

  case "$action" in
    snapshot)
      snapshot
      ;;
    summary)
      summary
      ;;
    recent)
      recent_activity "${1:-}"
      ;;
    classify)
      classify_target "${1:-}"
      ;;
    capture)
      capture_pane "${1:-}" "${2:-120}"
      ;;
    children)
      show_children "${1:-}"
      ;;
    new-codex-session|new-codex)
      new_codex_session "${1:-}" "${@:2}"
      ;;
    open-session|open)
      open_wsl_terminal_window "${1:-}"
      ;;
    send-text)
      send_text "${1:-}" "${2:-}" "${3:-}"
      ;;
    send-keys)
      local target="${1:-}"
      require_target "$target"
      shift
      if [ "$#" -eq 0 ]; then
        echo "missing key names" >&2
        exit 2
      fi
      tmux send-keys -t "$target" "$@"
      ;;
    stop)
      stop_pane "${1:-}" "${@:2}"
      ;;
    kill-pane)
      require_target "${1:-}"
      require_yes "${2:-}"
      tmux kill-pane -t "$1"
      ;;
    kill-window)
      require_target "${1:-}"
      require_yes "${2:-}"
      tmux kill-window -t "$1"
      ;;
    kill-session)
      require_target "${1:-}"
      require_yes "${2:-}"
      tmux kill-session -t "$1"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echo "unknown action: $action" >&2
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
