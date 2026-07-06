#!/usr/bin/env bash

# Shared helpers for distinguishing an occupied worktree from one that is still
# producing terminal output. A quiet tmux pane is not treated as busy.

count_processes_under() {
  local root="$1"
  local count=0
  local proc cwd

  [[ -d /proc && -d "$root" ]] || { echo 0; return; }

  for proc in /proc/[0-9]*; do
    [[ -e "$proc/cwd" ]] || continue
    cwd="$(readlink "$proc/cwd" 2>/dev/null || true)"
    if [[ "$cwd" == "$root" || "$cwd" == "$root"/* ]]; then
      count=$((count + 1))
    fi
  done

  echo "$count"
}

tmux_panes_under() {
  local root="$1"
  local session window pane cwd cmd title

  command -v tmux >/dev/null 2>&1 || return 0

  while IFS='|' read -r session window pane cwd cmd title; do
    [[ -n "$session" ]] || continue
    [[ "$cwd" == "$root" || "$cwd" == "$root"/* ]] || continue
    printf '%s|%s|%s|%s|%s|%s|%s:%s.%s\n' \
      "$session" "$window" "$pane" "$cwd" "$cmd" "$title" "$session" "$window" "$pane"
  done < <(tmux list-panes -a -F '#{session_name}|#{window_index}|#{pane_index}|#{pane_current_path}|#{pane_current_command}|#{pane_title}' 2>/dev/null || true)
}

pane_capture_hash() {
  local target="$1"
  tmux capture-pane -pt "$target" -S -200 2>/dev/null | sha256sum | awk '{print $1}'
}

count_busy_tmux_panes_under() {
  local root="$1"
  local settle_seconds="${2:-3}"
  local pane_count=0
  local busy_count=0
  local idle_count=0
  local line target before after
  local before_lines=()

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    target="${line##*|}"
    before="$(pane_capture_hash "$target")"
    before_lines+=("$target|$before")
    pane_count=$((pane_count + 1))
  done < <(tmux_panes_under "$root")

  if [[ "$pane_count" == "0" ]]; then
    printf '0 0 0\n'
    return
  fi

  if [[ "$settle_seconds" =~ ^[0-9]+$ && "$settle_seconds" -gt 0 ]]; then
    sleep "$settle_seconds"
  fi

  for line in "${before_lines[@]}"; do
    target="${line%%|*}"
    before="${line#*|}"
    after="$(pane_capture_hash "$target")"
    if [[ -n "$before" && "$before" != "$after" ]]; then
      busy_count=$((busy_count + 1))
    else
      idle_count=$((idle_count + 1))
    fi
  done

  printf '%s %s %s\n' "$pane_count" "$busy_count" "$idle_count"
}

worktree_activity_summary() {
  local root="$1"
  local settle_seconds="${2:-3}"
  local occupied pane_count busy_count idle_count

  occupied="$(count_processes_under "$root")"
  read -r pane_count busy_count idle_count <<<"$(count_busy_tmux_panes_under "$root" "$settle_seconds")"

  # If a worktree has processes but no tmux pane to observe, treat that activity
  # as busy/unknown. The stopped-output relaxation only applies to observable
  # panes that stayed unchanged during the settle window.
  if [[ "$occupied" != "0" && "$pane_count" == "0" ]]; then
    busy_count="$occupied"
  fi

  printf '%s %s %s %s\n' "$occupied" "$pane_count" "$busy_count" "$idle_count"
}
