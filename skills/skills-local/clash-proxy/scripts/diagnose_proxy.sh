#!/usr/bin/env bash
set -u

section() {
  printf '\n## %s\n' "$1"
}

redact() {
  sed -E \
    -e 's#(https?://)[^/@[:space:]]+:[^/@[:space:]]+@#\1***:***@#g' \
    -e 's#(socks5h?://)[^/@[:space:]]+:[^/@[:space:]]+@#\1***:***@#g' \
    -e 's#([?&](token|secret|password|passwd|pwd|key)=)[^&[:space:]]+#\1***#Ig' \
    -e 's#(url: https?://)[^[:space:]]+#\1***#Ig'
}

run() {
  local title="$1"
  shift
  section "$title"
  "$@" 2>&1 | redact || true
}

have() {
  command -v "$1" >/dev/null 2>&1
}

windows_user_dirs() {
  find /mnt/c/Users -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
    | grep -Ev '/(All Users|Default|Default User|Public)$' || true
}

wsl_gateway() {
  ip route show default 2>/dev/null | awk '/default/ {print $3; exit}'
}

usable_windows_gateway() {
  local gateway
  gateway="$(wsl_gateway)"
  case "$gateway" in
    ""|198.18.*) return ;;
  esac
  printf '%s\n' "$gateway"
}

proxy_env() {
  env | grep -Ei '^(HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|http_proxy|https_proxy|all_proxy|no_proxy)=' | sort || true
}

windows_user_proxy() {
  powershell.exe -NoProfile -Command "Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' | Select-Object ProxyEnable,ProxyServer,AutoConfigURL,ProxyOverride | Format-List"
}

windows_proxy_processes() {
  powershell.exe -NoProfile -Command "Get-Process | Where-Object { \$_.ProcessName -match 'clash|mihomo|verge|sing-box|v2ray|nekoray|hiddify' } | Select-Object Id,ProcessName,Path | Format-Table -AutoSize"
}

clash_config_summary() {
  shopt -s nullglob
  local dirs=()
  local user_dir
  while IFS= read -r user_dir; do
    dirs+=(
      "$user_dir/AppData/Roaming/io.github.clash-verge-rev.clash-verge-rev"
      "$user_dir/AppData/Roaming/Clash Verge"
      "$user_dir/AppData/Roaming/Clash for Windows"
      "$user_dir/.config/clash"
      "$user_dir/.config/mihomo"
    )
  done < <(windows_user_dirs)

  local dir
  for dir in "${dirs[@]}"; do
    [ -d "$dir" ] || continue
    printf 'config_dir=%s\n' "$dir"
    find "$dir" -maxdepth 2 -type f \( -iname '*.yaml' -o -iname '*.yml' \) -printf '  %p (%s bytes)\n' 2>/dev/null | head -40
    local file
    for file in "$dir"/config.yaml "$dir"/clash-verge.yaml "$dir"/verge.yaml "$dir"/profiles/Merge.yaml; do
      [ -f "$file" ] || continue
      printf '\n  key summary: %s\n' "$file"
      grep -nE '^(mixed-port|port|socks-port|redir-port|tproxy-port|allow-lan|bind-address|mode|log-level|ipv6|unified-delay|tcp-concurrent|external-controller|tun:|dns:|profile:|proxy-groups:|rule-providers:|rules:)' "$file" 2>/dev/null | head -80
    done
  done
}

listener_summary() {
  if have ss; then
    ss -ltnp 2>/dev/null | grep -E ':(4062|7890|7897|7898|7899|9090|9097|1053|15721)\b' || true
  else
    netstat -ltnp 2>/dev/null | grep -E ':(4062|7890|7897|7898|7899|9090|9097|1053|15721)\b' || true
  fi
}

curl_probe() {
  local label="$1"
  local proxy="$2"
  local url="$3"
  if [ -n "$proxy" ]; then
    curl -x "$proxy" -o /dev/null -sS -w "$label proxy=$proxy code=%{http_code} time=%{time_total}\n" --max-time 6 "$url" 2>&1 | redact || true
  else
    curl --noproxy '*' -o /dev/null -sS -w "$label direct code=%{http_code} time=%{time_total}\n" --max-time 6 "$url" 2>&1 | redact || true
  fi
}

can_connect() {
  local host="$1"
  local port="$2"
  timeout 1 bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1
}

network_probes() {
  if ! have curl; then
    echo "curl not found; skipping network probes"
    return
  fi

  curl_probe "msftconnecttest" "" "http://www.msftconnecttest.com/connecttest.txt"

  local gateway
  gateway="$(usable_windows_gateway)"
  local candidates=()
  local value
  for value in "${HTTP_PROXY:-}" "${http_proxy:-}" "${HTTPS_PROXY:-}" "${https_proxy:-}" "${ALL_PROXY:-}" "${all_proxy:-}"; do
    [ -n "$value" ] && candidates+=("$value")
  done
  for port in 4062 7890 7897 7898 7899; do
    if can_connect "127.0.0.1" "$port"; then
      candidates+=("http://127.0.0.1:$port")
    elif [ -n "$gateway" ] && can_connect "$gateway" "$port"; then
      candidates+=("http://$gateway:$port")
    fi
  done

  local seen=" "
  local proxy
  for proxy in "${candidates[@]}"; do
    case "$seen" in
      *" $proxy "*) continue ;;
    esac
    seen="$seen$proxy "
    curl_probe "gstatic204" "$proxy" "https://www.gstatic.com/generate_204"
  done
}

section "Basic"
printf 'date=%s\n' "$(date -Is)"
printf 'kernel=%s\n' "$(uname -a)"
printf 'wsl_gateway=%s\n' "$(wsl_gateway)"
if [ -z "$(usable_windows_gateway)" ] && [ "$(wsl_gateway)" != "" ]; then
  printf 'wsl_gateway_note=%s\n' "default gateway looks like TUN/fake-ip; skipping it as a Windows proxy host"
fi
printf 'resolv_conf_nameserver=%s\n' "$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf 2>/dev/null)"

run "WSL proxy environment" proxy_env
run "Listening proxy-like ports in WSL namespace" listener_summary

if have powershell.exe; then
  run "Windows proxy-related processes" windows_proxy_processes
  run "Windows user proxy registry" windows_user_proxy
else
  section "Windows checks"
  echo "powershell.exe not found; not running from WSL or Windows interop is disabled"
fi

if have netsh.exe; then
  run "Windows WinHTTP proxy" netsh.exe winhttp show proxy
fi

run "Clash/Mihomo config summary" clash_config_summary
run "Connectivity probes" network_probes
