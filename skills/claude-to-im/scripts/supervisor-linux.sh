#!/usr/bin/env bash
# Linux supervisor — prefer systemd --user when installed, fall back to setsid/nohup.
# Sourced by daemon.sh; expects CTI_HOME, SKILL_DIR, PID_FILE, STATUS_FILE, LOG_FILE.

SYSTEMD_UNIT="claude-to-im.service"
SYSTEMD_DIR="$HOME/.config/systemd/user"
SYSTEMD_FILE="$SYSTEMD_DIR/$SYSTEMD_UNIT"

systemd_user_available() {
  command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1
}

systemd_service_installed() {
  [ -f "$SYSTEMD_FILE" ]
}

escape_systemd_value() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

build_service_path() {
  local node_dir codex_dir path_value
  node_dir="$(dirname "$(command -v node)")"
  path_value="$node_dir"
  if command -v codex >/dev/null 2>&1; then
    codex_dir="$(dirname "$(command -v codex)")"
    if [ "$codex_dir" != "$node_dir" ]; then
      path_value="$path_value:$codex_dir"
    fi
  fi
  printf '%s:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' "$path_value"
}

generate_systemd_unit() {
  local node_path service_path
  node_path="$(command -v node)"
  service_path="$(build_service_path)"

  mkdir -p "$SYSTEMD_DIR"
  cat > "$SYSTEMD_FILE" <<EOF
[Unit]
Description=claude-to-im bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment="HOME=$(escape_systemd_value "$HOME")"
Environment="CTI_HOME=$(escape_systemd_value "$CTI_HOME")"
Environment="PATH=$(escape_systemd_value "$service_path")"
EnvironmentFile=$(escape_systemd_value "$CTI_HOME/config.env")
WorkingDirectory=$(escape_systemd_value "$SKILL_DIR")
ExecStartPre=/usr/bin/test -f $(escape_systemd_value "$CTI_HOME/config.env")
ExecStartPre=/bin/mkdir -p $(escape_systemd_value "$CTI_HOME/data") $(escape_systemd_value "$CTI_HOME/logs") $(escape_systemd_value "$CTI_HOME/runtime") $(escape_systemd_value "$CTI_HOME/data/messages")
ExecStart=$(escape_systemd_value "$node_path") $(escape_systemd_value "$SKILL_DIR/dist/daemon.mjs")
Restart=always
RestartSec=5
TimeoutStopSec=20
KillSignal=SIGTERM

[Install]
WantedBy=default.target
EOF
}

supervisor_install_service() {
  ensure_dirs
  ensure_built

  if ! systemd_user_available; then
    echo "systemd --user is not available in this Linux session."
    echo "Tip: on WSL, enable systemd for the distro before using install-service."
    return 1
  fi

  generate_systemd_unit
  systemctl --user daemon-reload
  systemctl --user enable "$SYSTEMD_UNIT" >/dev/null

  echo "Installed systemd --user unit: $SYSTEMD_FILE"
  echo "Enabled at login: $SYSTEMD_UNIT"
  echo "Start with:  bash \"$SKILL_DIR/scripts/daemon.sh\" start"
  echo "Stop with:   bash \"$SKILL_DIR/scripts/daemon.sh\" stop"
}

supervisor_uninstall_service() {
  if ! systemd_user_available; then
    echo "systemd --user is not available in this Linux session."
    return 1
  fi

  systemctl --user stop "$SYSTEMD_UNIT" >/dev/null 2>&1 || true
  systemctl --user disable "$SYSTEMD_UNIT" >/dev/null 2>&1 || true
  rm -f "$SYSTEMD_FILE"
  systemctl --user daemon-reload
  rm -f "$PID_FILE"

  echo "Removed systemd --user unit: $SYSTEMD_FILE"
}

supervisor_start() {
  if supervisor_is_managed; then
    systemctl --user daemon-reload
    systemctl --user start "$SYSTEMD_UNIT"
    return 0
  fi

  if command -v setsid >/dev/null 2>&1; then
    setsid node "$SKILL_DIR/dist/daemon.mjs" >> "$LOG_FILE" 2>&1 < /dev/null &
  else
    nohup node "$SKILL_DIR/dist/daemon.mjs" >> "$LOG_FILE" 2>&1 < /dev/null &
  fi
  # Fallback: write shell $! as PID; main.ts will overwrite with real PID
  echo $! > "$PID_FILE"
}

supervisor_stop() {
  local pid
  pid=$(read_pid)

  if supervisor_is_managed; then
    systemctl --user stop "$SYSTEMD_UNIT" >/dev/null 2>&1 || true
  fi

  if [ -n "$pid" ] && pid_alive "$pid"; then
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 10); do
      pid_alive "$pid" || break
      sleep 1
    done
    pid_alive "$pid" && kill -9 "$pid" 2>/dev/null || true
  elif ! supervisor_is_managed; then
    echo "Bridge was not running (stale PID file)"
  fi

  rm -f "$PID_FILE"
}

supervisor_is_managed() {
  systemd_user_available && systemd_service_installed
}

supervisor_status_extra() {
  if supervisor_is_managed; then
    echo "Bridge is registered with systemd --user ($SYSTEMD_UNIT)"
    echo "Unit enabled: $(systemctl --user is-enabled "$SYSTEMD_UNIT" 2>/dev/null || echo unknown)"
    echo "Unit active:  $(systemctl --user is-active "$SYSTEMD_UNIT" 2>/dev/null || echo unknown)"
  fi
}

supervisor_is_running() {
  if supervisor_is_managed && systemctl --user is-active --quiet "$SYSTEMD_UNIT"; then
    return 0
  fi

  local pid
  pid=$(read_pid)
  pid_alive "$pid"
}
