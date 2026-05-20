#!/usr/bin/env bash
set -u

port_from_config() {
  local file
  for file in /mnt/c/Users/*/AppData/Roaming/io.github.clash-verge-rev.clash-verge-rev/config.yaml \
              /mnt/c/Users/*/AppData/Roaming/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml \
              /mnt/c/Users/*/.config/mihomo/config.yaml \
              /mnt/c/Users/*/.config/clash/config.yaml; do
    [ -f "$file" ] || continue
    awk -F: '/^mixed-port:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$file"
    return
  done
}

wsl_gateway() {
  ip route show default 2>/dev/null | awk '/default/ {print $3; exit}'
}

can_connect() {
  local host="$1"
  local port="$2"
  timeout 1 bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1
}

port="${1:-${CLASH_MIXED_PORT:-}}"
if [ -z "$port" ]; then
  port="$(port_from_config)"
fi
if [ -z "$port" ]; then
  port=7890
fi

gateway="$(wsl_gateway)"
host="127.0.0.1"
if ! can_connect "$host" "$port" && [ -n "$gateway" ] && can_connect "$gateway" "$port"; then
  host="$gateway"
fi

proxy_url="http://$host:$port"
socks_url="socks5h://$host:$port"
no_proxy="localhost,127.0.0.1,::1,.local,*.local"
if [ -n "$gateway" ]; then
  no_proxy="$no_proxy,$gateway"
fi

cat <<EOF
export http_proxy="$proxy_url"
export https_proxy="$proxy_url"
export HTTP_PROXY="$proxy_url"
export HTTPS_PROXY="$proxy_url"
export all_proxy="$socks_url"
export ALL_PROXY="$socks_url"
export no_proxy="$no_proxy"
export NO_PROXY="$no_proxy"
EOF
