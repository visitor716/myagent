---
name: my-clash-proxy
description: "Diagnose and safely configure Windows and WSL proxy networking. Use when the user mentions Windows proxy, WSL proxy, Clash, Clash Verge, Mihomo, sing-box, V2Ray, system proxy, WinHTTP, TUN, DNS hijack, aTrust, 深信服/Sangfor VPN, company intranet split routing, 企业微信内网访问, Clash/aTrust conflicts, Codex Desktop Reconnecting, Codex/Claude proxy env, gateway/worktree proxy inheritance, http_proxy/https_proxy/all_proxy, tmux proxy inheritance, proxy region policy such as US-first Japan-fallback no-Hong-Kong, or asks about Windows/WSL 网络代理/代理软件/代理环境."
---
> Trigger stats (myagent-trigger-stats): when this skill is used, run `python3 /home/zhanxp/projects/myagent/skills/scripts/record_skill_trigger.py my-clash-proxy` once near the start; if it fails, continue.


# Windows WSL Proxy

## Overview

Use this skill to inspect and fix proxy routing across Windows, WSL, and local tools. Prefer read-only diagnosis first; only change Windows proxy settings, aTrust settings, shell startup files, tmux services, or Clash/Mihomo configs after the user explicitly asks for a change.

Treat subscription URLs, node servers, passwords, tokens, proxy credentials, company intranet domains, VPN credentials, and internal IP ranges as secrets. Mask them in summaries and avoid printing full proxy/node config blocks.

## Default Workflow

1. Identify the target scope:
   - Windows system proxy, WinHTTP, Clash/Mihomo/TUN, aTrust/Sangfor VPN, company intranet routing, WSL shell env, tmux/systemd process env, or a specific app.
   - If the user only asks to "check" or "diagnose", stay read-only.

2. Run the read-only snapshot first:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/clash-proxy/scripts/diagnose_proxy.sh
```

3. Summarize evidence, not guesses:
   - Active Clash/Mihomo app and likely config directory.
   - Mixed/http/socks ports and whether WSL can reach them through `127.0.0.1` or the Windows gateway.
   - Windows user proxy and WinHTTP proxy state.
   - aTrust/Sangfor process, adapter, route, and DNS evidence when present.
   - WSL `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, and `NO_PROXY`.
   - Codex Desktop/app-server, Codex CLI, Claude Code, gateway, tmux, and worker process proxy inheritance when relevant.
   - TUN/DNS/IPv6 risks visible in config or logs.
   - Whether target processes inherited proxy env.

4. Run focused follow-up probes only when needed:
   - `curl -x http://127.0.0.1:<port> ...` for local proxy.
   - `curl -x http://<wsl-gateway>:<port> ...` when `127.0.0.1` fails from WSL.
   - `tr '\0' '\n' < /proc/<pid>/environ | rg -i 'proxy'` for tmux/systemd/app env.
   - `route.exe print -4` or `Get-NetRoute -AddressFamily IPv4` for Windows route ownership.
   - Clash/Mihomo logs for `timeout`, `dns`, `tun`, `bind6`, `provider`, or `rule` evidence.

## aTrust + Clash Coexistence

Target topology:

- Company intranet traffic uses aTrust/Sangfor routes and DNS.
- Normal public traffic uses Clash through Windows system proxy or Clash mixed-port.
- WSL development is opt-in: temporary proxy exports for public dependency downloads, no global proxy export for intranet work unless the user asks for persistence.

Preferred setup:

1. Connect aTrust and let it own company intranet routes and DNS.
2. Keep Clash in system-proxy or mixed-port mode for public traffic.
3. Keep Clash TUN/VPN mode off unless there is a specific reason to enable it and route evidence shows it does not override aTrust.
4. Add `DIRECT` rules for company domains and intranet IP ranges in Clash profile enhancement rules, not generated runtime files.
5. Add matching `NO_PROXY` entries in temporary WSL proxy exports when a WSL tool must reach company intranet directly.

Example Clash guidance with placeholders only:

```yaml
rules:
  - DOMAIN-SUFFIX,<company-domain>,DIRECT
  - DOMAIN-KEYWORD,<company-keyword>,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,100.64.0.0/10,DIRECT,no-resolve
```

Use exact company domains and CIDRs only when the user supplies them in the current task, and do not repeat them in final summaries.

Decision rules:

- If aTrust forces a Windows default route such as `0.0.0.0/0` through its adapter, do not try to fight it with blind local route edits. Recommend IT-side aTrust split tunnel policy first. If that is unavailable, use app/browser-level Clash proxy or Windows system proxy while keeping Clash TUN off.
- If company domains fail only when Clash proxy/system proxy is enabled, inspect Clash rule order, Windows proxy bypass, and WSL `NO_PROXY`. Add company domains/IPs to Clash `DIRECT` and to temporary `NO_PROXY` for the affected shell or app.
- If public traffic fails only when aTrust is connected, compare Windows default routes and DNS adapters. A forced full-tunnel aTrust policy can capture public traffic before Clash unless Clash is used as an explicit app/system proxy.
- If WSL breaks after enabling proxy exports, inspect `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, and `NO_PROXY`, then remove global exports for intranet work. Prefer one-shell temporary exports from `print_wsl_proxy_exports.sh`.
- If Clash TUN and aTrust are both active, suspect route and DNS ownership conflicts first. Disable Clash TUN for diagnosis before changing aTrust or Windows network state.

## Safe Fix Patterns

### WSL shell proxy

To print WSL exports without editing files:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/clash-proxy/scripts/print_wsl_proxy_exports.sh
```

Use the printed exports temporarily first. Append to `~/.bashrc`, `~/.zshrc`, or profile files only when the user asks for persistent setup, and back up the target file first.

For Codex/Claude CLI defaults in WSL:

- Prefer the existing `~/.wsl-proxy.env` helper and `proxyon`; it should discover or use the saved current port, export `HTTP_PROXY`/`HTTPS_PROXY` plus lowercase variants, set `NO_PROXY`, and keep `ALL_PROXY` unset unless a task explicitly needs it.
- Verify wrapper inheritance with:

```bash
bash -ic 'type codex; type claude; type hermes; WSL_PROXY_QUIET=1 proxyon; env | rg -i "^(HTTP_PROXY|HTTPS_PROXY|http_proxy|https_proxy|NO_PROXY|no_proxy|ALL_PROXY|all_proxy)="'
```

- Do not hardcode `4062` in new instructions. First read the live Windows proxy and Clash/Mihomo config; use the actual `mixed-port` or HTTP `port` that passes a proxied curl probe.

### Codex Desktop / app-server reconnecting

When Codex Desktop, Codex App, or app-server is stuck on `Reconnecting`, treat proxy env as one possible cause, not the only cause.

1. Detect the actual HTTP-capable endpoint first:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/clash-proxy/scripts/diagnose_proxy.sh
curl -I -m 12 -x http://127.0.0.1:<port> https://api.openai.com
```

Use `mixed-port` or HTTP `port`; do not use the SOCKS-only port for `HTTP_PROXY`.

2. Create or update `~/.codex/.env`, preserving unrelated keys:

```bash
HTTP_PROXY="http://127.0.0.1:<actual-http-or-mixed-port>"
HTTPS_PROXY="http://127.0.0.1:<actual-http-or-mixed-port>"
```

Back up an existing file before editing. Keep quotes, and do not print auth files or tokens.

3. Validate parsing and the live app-server environment:

```bash
set -a; . ~/.codex/.env; set +a
printf '%s\n' "$HTTP_PROXY" "$HTTPS_PROXY"
codex app-server daemon version
pid="$(pgrep -f 'codex app-server --remote-control' | head -n1)"
tr '\0' '\n' < "/proc/$pid/environ" | rg -i '^(HTTP_PROXY|HTTPS_PROXY|http_proxy|https_proxy|NO_PROXY|no_proxy)='
```

4. Restart guidance:
   - If restarting would break the current active Codex session, report exact commands instead of doing it silently.
   - Otherwise run `codex app-server daemon restart`, then ask the user to fully quit Codex Desktop from the Windows tray or Task Manager and reopen it.

If reconnecting continues after the proxy env is correct, inspect Codex Desktop/app-server socket and daemon logs next; do not keep changing Clash blindly.

### Codex proxy port drift

Common silent failure: Clash/Mihomo restarted or refreshed its profile, the live HTTP or
mixed port changed, and `~/.codex/.env` still points Codex Desktop/app-server at the old
dead port. A shell-level `curl` can still work if the shell inherited a different proxy,
so compare the live proxy endpoint with the environment that Codex actually inherited.

Symptoms:
- `codex exec "..."` shows `Reconnecting... 1/12` with no real progress.
- `codex doctor` reports reachability failure for the ChatGPT base URL.
- `codex auth login` fails with `error sending request for url` during token exchange.
- Shell `curl https://api.openai.com` works because the shell is not using the stale port.

Triage:

```bash
# 1. Find the live HTTP-capable Clash/Mihomo endpoint.
bash /home/zhanxp/projects/myagent/skills/skills-local/clash-proxy/scripts/diagnose_proxy.sh

for port in 4065 4062 7890 9090; do
  curl -fsS --max-time 4 -x "http://127.0.0.1:${port}" https://httpbin.org/ip >/dev/null \
    && printf 'alive: http://127.0.0.1:%s\n' "$port"
done

# 2. Compare with Codex's persisted app-server environment.
if [ -f ~/.codex/.env ]; then
  grep -E '^(HTTP_PROXY|HTTPS_PROXY|http_proxy|https_proxy)=' ~/.codex/.env
fi

# 3. If a running app-server exists, compare the real process environment too.
pid="$(pgrep -f 'codex app-server --remote-control' | head -n1 || true)"
if [ -n "$pid" ]; then
  tr '\0' '\n' < "/proc/$pid/environ" | rg -i '^(HTTP_PROXY|HTTPS_PROXY|http_proxy|https_proxy|NO_PROXY|no_proxy)='
fi
```

Fix when port drifted:

```bash
# Backup first, preserving unrelated keys in ~/.codex/.env.
cp ~/.codex/.env ~/.codex/.env.bak.$(date +%Y%m%d-%H%M%S)

# Replace only loopback HTTP proxy ports. Fill in <live-port> from the triage result.
sed -i -E 's#http://127\.0\.0\.1:[0-9]+#http://127.0.0.1:<live-port>#g' ~/.codex/.env

# Validate parsing before restarting anything.
set -a; . ~/.codex/.env; set +a
printf '%s\n' "$HTTP_PROXY" "$HTTPS_PROXY"
```

Do not change Clash to match Codex's stale port. Update Codex to the live Clash/Mihomo
HTTP or mixed port. Restart the app-server only after deciding it will not interrupt the
current active Codex session; otherwise report the exact restart command for the user.

### Codex auth vs proxy: which is broken?

When Codex is unusable, proxy and auth failures can look identical from symptoms alone.
Diagnose in strict order:

```text
1. Proxy first: curl -x http://127.0.0.1:<port> https://httpbin.org/ip
2. Auth second: ls ~/.codex/auth.json && codex doctor | grep 'auth '
3. Provider last: codex doctor | grep reachability
```

For `chatgpt-http`, `OPENAI_API_KEY` is not the credential path. Codex uses OAuth for this
provider. The token lives in `~/.codex/auth.json`, created by `codex auth login`.
`codex doctor` reports `auth mode: chatgpt` for this configuration. If `auth.json` is
missing or expired, fix login instead of setting an API key.

WSL callback gotcha for `codex auth login`: the command starts a local callback server on
`localhost:1455`. A Windows browser cannot always reach WSL's localhost, so after OAuth
login the redirect to `localhost:1455/auth/callback?code=...` can fail with connection
refused. Replace `localhost` in the browser address bar with the WSL IP from
`ip addr show eth0 | grep 'inet '`, then load the adjusted callback URL so WSL receives
the code and creates `~/.codex/auth.json`.

### tg-agent-gateway and worktree worker inheritance

For `tg-agent-gateway`, gateway-launched Codex/Claude/Hermes workers inherit the gateway process env. To make future worker runs use the proxy by default:

- Add or update the local project `.env` with the actual endpoint:

```bash
TG_GATEWAY_PROXY_URL="http://127.0.0.1:<actual-http-or-mixed-port>"
HTTP_PROXY="http://127.0.0.1:<actual-http-or-mixed-port>"
HTTPS_PROXY="http://127.0.0.1:<actual-http-or-mixed-port>"
http_proxy="http://127.0.0.1:<actual-http-or-mixed-port>"
https_proxy="http://127.0.0.1:<actual-http-or-mixed-port>"
NO_PROXY="localhost,127.0.0.1,::1,.local,*.local,host.docker.internal,gateway.docker.internal,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.64.0.0/10,169.254.0.0/16"
no_proxy="localhost,127.0.0.1,::1,.local,*.local,host.docker.internal,gateway.docker.internal,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.64.0.0/10,169.254.0.0/16"
```

- Also update existing worktree `.env` files if they exist. Do not create token-filled `.env` files in clean worktrees just for proxy inheritance unless the worktree is launched standalone.
- Restart gateway with the repo's restart script when runtime inheritance must take effect:

```bash
bash scripts/restart-gateway.sh
```

- Verify the running gateway and child tools, not just the file:

```bash
pid="$(pgrep -f 'node dist/index.js' | head -n1)"
tr '\0' '\n' < "/proc/$pid/environ" | rg -i '^(HTTP_PROXY|HTTPS_PROXY|http_proxy|https_proxy|NO_PROXY|no_proxy|TG_GATEWAY_PROXY_URL)='
```

Global `npm config set proxy` is usually unnecessary and can break intranet work; prefer shell/project env unless a package manager is the only failing surface.

### Windows system proxy and WinHTTP

Read state with:

```bash
powershell.exe -NoProfile -Command "Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' | Select ProxyEnable,ProxyServer,AutoConfigURL,ProxyOverride | Format-List"
netsh.exe winhttp show proxy
```

Do not run `netsh winhttp import proxy`, registry writes, or Settings changes unless the user explicitly asks to modify Windows proxy behavior.

### Clash Verge / Mihomo

Prefer editing profile enhancement files or UI settings over generated runtime files:

- Generated runtime files such as `clash-verge.yaml` can be overwritten by the app.
- Profile enhancement files under `profiles/` are safer for prepend/append/delete rules.
- Back up any YAML before editing.
- Do not print subscription URLs, `server`, `password`, `uuid`, `token`, or full `proxies:` entries.

Use the region policy helper for requests like "use US first, fallback to Japan, never Hong Kong":

```bash
# Dry-run summary only; no writes.
python3 /home/zhanxp/projects/myagent/skills/skills-local/clash-proxy/scripts/clash_region_policy.py

# Apply to the active Clash Verge profile script and current runtime files, then validate with Mihomo.
python3 /home/zhanxp/projects/myagent/skills/skills-local/clash-proxy/scripts/clash_region_policy.py \
  --write-profile-script \
  --update-selected \
  --apply-runtime \
  --validate-exe /mnt/d/Software/vpn/verge-mihomo.exe
```

After applying region policy, restart Clash Verge only if the running core still logs the old groups. Use single-quoted PowerShell from Bash so `$path` is not expanded by Bash:

```bash
powershell.exe -NoProfile -Command '$path = "D:\Software\vpn\clash-verge.exe"; Stop-Process -Name clash-verge -Force -ErrorAction SilentlyContinue; Stop-Process -Name verge-mihomo -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2; Start-Process -FilePath $path'
```

Verify after restart with:

```bash
tail -n 80 /mnt/c/Users/<WindowsUser>/AppData/Roaming/io.github.clash-verge-rev.clash-verge-rev/logs/service/service_latest.log | rg 'US-Japan|Hong Kong|SSRDOG|match'
```

Common stability checks:

- `ipv6: true` with `bind6` warnings can cause direct route failures; try disabling IPv6 if logs support that diagnosis.
- Windows connectivity checks should usually be direct: `msftconnecttest.com`, `msftncsi.com`.
- NTP UDP/123 should usually be direct.
- `allow-lan: true` should be disabled or constrained when only local proxying is needed.
- TUN `strict-route` improves leak prevention but can affect VirtualBox, WSL, or LAN tools.
- Runtime YAML edits prove immediate state, but profile script edits make the policy survive subscription refreshes.
- Delete temporary transformed config files after validation if they contain full proxy/node fields; keep timestamped backups for rollback.

### tmux, service, and app inheritance

When an app works manually but fails in a service or tmux session, compare proxy env:

```bash
env | rg -i '^(https?_proxy|all_proxy|no_proxy)='
pid=<target-pid>
tr '\0' '\n' < "/proc/$pid/environ" | rg -i '^(https?_proxy|all_proxy|no_proxy)='
```

Fix the launcher or service unit so it exports proxy variables before starting the app. Restart only the affected process after the user asks for runtime changes.

## Reporting

Use this compact report shape:

- `Current State`: active proxy app/config, port, Windows proxy state, WSL env.
- `Findings`: concrete issues with evidence.
- `Recommended Fix`: lowest-risk fix first.
- `Commands Run`: commands or scripts used, with secrets redacted.
- `Changed Files`: only include if you actually edited persistent config.
