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

windows_winhttp_proxy() {
  if have netsh.exe; then
    netsh.exe winhttp show proxy
  else
    powershell.exe -NoProfile -Command "netsh winhttp show proxy"
  fi
}

windows_proxy_processes() {
  powershell.exe -NoProfile -Command "Get-Process | Where-Object { \$_.ProcessName -match 'clash|mihomo|verge|sing-box|v2ray|nekoray|hiddify' } | Select-Object Id,ProcessName,Path | Format-Table -AutoSize"
}

windows_atrust_processes() {
  powershell.exe -NoProfile -Command "Get-Process | Where-Object { \$_.ProcessName -match 'atrust|sangfor|easyconnect|sfvpn|sangforcsclient' } | Select-Object Id,ProcessName,Path | Format-Table -AutoSize"
}

windows_vpn_adapter_summary() {
  powershell.exe -NoProfile -Command '
$patterns = "atrust|sangfor|easyconnect|vpn|tun|tap|wintun|mihomo|clash|virtual"
Get-NetAdapter |
  Where-Object { $_.Name -match $patterns -or $_.InterfaceDescription -match $patterns } |
  Sort-Object Name |
  Select-Object Name,InterfaceDescription,Status,ifIndex,LinkSpeed |
  Format-Table -AutoSize
'
}

windows_route_summary() {
  powershell.exe -NoProfile -Command '
$patterns = "atrust|sangfor|easyconnect|vpn|tun|tap|wintun|mihomo|clash|virtual"
$interestingPrefix = "^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.|198\.18\.)"
$routes = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object {
    $_.DestinationPrefix -in @("0.0.0.0/0", "0.0.0.0/1", "128.0.0.0/1") -or
    $_.DestinationPrefix -match $interestingPrefix -or
    $_.InterfaceAlias -match $patterns
  } |
  Sort-Object DestinationPrefix,RouteMetric,InterfaceMetric

if ($routes) {
  $routes |
    Select-Object DestinationPrefix,InterfaceAlias,NextHop,RouteMetric,InterfaceMetric,PolicyStore |
    Format-Table -AutoSize
} else {
  "no default/private/VPN-like IPv4 routes found by Get-NetRoute"
}

$vpnDefault = $routes | Where-Object {
  $_.DestinationPrefix -eq "0.0.0.0/0" -and $_.InterfaceAlias -match $patterns
}
if ($vpnDefault) {
  "hint=VPN-like adapter owns 0.0.0.0/0; aTrust may be in full-tunnel mode. Prefer IT split tunnel or app/system-proxy Clash, with Clash TUN off."
}
'
}

windows_vpn_dns_summary() {
  powershell.exe -NoProfile -Command '
$patterns = "atrust|sangfor|easyconnect|vpn|tun|tap|wintun|mihomo|clash|virtual"
Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.InterfaceAlias -match $patterns } |
  Sort-Object InterfaceAlias |
  Select-Object InterfaceAlias,@{Name="AddressFamily"; Expression = { "IPv4" }},ServerAddresses |
  Format-Table -AutoSize
'
}

sanitize_rule_line() {
  sed -E \
    -e 's#((DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD)[[:space:]]*,[[:space:]]*)[^,[:space:]]+#\1<domain-redacted>#Ig' \
    -e 's#((IP-CIDR|IP-CIDR6)[[:space:]]*,[[:space:]]*)[^,[:space:]]+#\1<ip-redacted>#Ig' \
    -e 's#((RULE-SET)[[:space:]]*,[[:space:]]*)[^,[:space:]]+#\1<rule-set-redacted>#Ig' \
    -e 's#([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?#<ip-redacted>#g' \
    -e 's#([A-Za-z0-9_-]+\.)+[A-Za-z][A-Za-z0-9-]{1,}#<domain-redacted>#g'
}

clash_file_hints() {
  local file="$1"

  printf '\n  key summary: %s\n' "$file"
  grep -nE '^(mixed-port|port|socks-port|redir-port|tproxy-port|allow-lan|bind-address|mode|log-level|ipv6|unified-delay|tcp-concurrent|external-controller|tun:|dns:|profile:|proxy-groups:|rule-providers:|rules:)' "$file" 2>/dev/null | head -80

  printf '\n  tun/dns selected hints: %s\n' "$file"
  awk '
    function scrub(line) {
      if (line ~ /^[[:space:]]+(default-nameserver|nameserver|fallback|proxy-server-nameserver|direct-nameserver|fallback-filter):/) {
        sub(/:.*/, ": <configured>", line)
      }
      return line
    }
    /^[[:space:]]*tun:[[:space:]]*$/ { section = "tun"; print NR ":" $0; next }
    /^[[:space:]]*dns:[[:space:]]*$/ { section = "dns"; print NR ":" $0; next }
    section != "" && /^[^[:space:]-]/ { section = "" }
    section == "tun" && /^[[:space:]]+(enable|stack|device|auto-route|auto-detect-interface|strict-route|dns-hijack):/ {
      print NR ":" scrub($0)
      next
    }
    section == "dns" && /^[[:space:]]+(enable|listen|ipv6|enhanced-mode|fake-ip-range|fake-ip-filter|use-hosts|default-nameserver|nameserver|fallback|proxy-server-nameserver|direct-nameserver|fallback-filter):/ {
      print NR ":" scrub($0)
      next
    }
  ' "$file" 2>/dev/null | head -80

  printf '\n  DIRECT rule hints (sanitized): %s\n' "$file"
  local direct_matches
  direct_matches="$(grep -nEi '^[[:space:]]*-[[:space:]]*(DOMAIN|DOMAIN-SUFFIX|DOMAIN-KEYWORD|IP-CIDR|IP-CIDR6|GEOIP|RULE-SET).*,[[:space:]]*DIRECT([,[:space:]]|$)' "$file" 2>/dev/null | head -80 | sanitize_rule_line)"
  if [ -n "$direct_matches" ]; then
    printf '%s\n' "$direct_matches"
  else
    echo "  no sanitized DIRECT domain/IP/rule-set entries found in sampled files"
  fi
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
      clash_file_hints "$file"
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
  run "Windows likely aTrust/Sangfor processes" windows_atrust_processes
  run "Windows proxy-related processes" windows_proxy_processes
  run "Windows VPN/TUN-like adapters" windows_vpn_adapter_summary
  run "Windows IPv4 routes (default/private/VPN-like)" windows_route_summary
  run "Windows VPN/TUN-like DNS clients" windows_vpn_dns_summary
  run "Windows user proxy registry" windows_user_proxy
else
  section "Windows checks"
  echo "powershell.exe not found; not running from WSL or Windows interop is disabled"
fi

if have netsh.exe; then
  run "Windows WinHTTP proxy" netsh.exe winhttp show proxy
elif have powershell.exe; then
  run "Windows WinHTTP proxy" windows_winhttp_proxy
fi

run "Clash/Mihomo config summary" clash_config_summary
run "Connectivity probes" network_probes
