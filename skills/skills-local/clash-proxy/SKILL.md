---
name: clash-proxy
description: "Diagnose and safely configure Windows and WSL proxy networking. Use when the user mentions Windows proxy, WSL proxy, Clash, Clash Verge, Mihomo, sing-box, V2Ray, system proxy, WinHTTP, TUN, DNS hijack, http_proxy/https_proxy/all_proxy, tmux proxy inheritance, proxy region policy such as US-first Japan-fallback no-Hong-Kong, or asks about Windows/WSL 网络代理/代理软件/代理环境."
---

# Windows WSL Proxy

## Overview

Use this skill to inspect and fix proxy routing across Windows, WSL, and local tools. Prefer read-only diagnosis first; only change Windows proxy settings, shell startup files, tmux services, or Clash/Mihomo configs after the user explicitly asks for a change.

Treat subscription URLs, node servers, passwords, tokens, and proxy credentials as secrets. Mask them in summaries and avoid printing full proxy/node config blocks.

## Default Workflow

1. Identify the target scope:
   - Windows system proxy, WinHTTP, Clash/Mihomo/TUN, WSL shell env, tmux/systemd process env, or a specific app.
   - If the user only asks to "check" or "diagnose", stay read-only.

2. Run the read-only snapshot first:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/clash-proxy/scripts/diagnose_proxy.sh
```

3. Summarize evidence, not guesses:
   - Active Clash/Mihomo app and likely config directory.
   - Mixed/http/socks ports and whether WSL can reach them through `127.0.0.1` or the Windows gateway.
   - Windows user proxy and WinHTTP proxy state.
   - WSL `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, and `NO_PROXY`.
   - TUN/DNS/IPv6 risks visible in config or logs.
   - Whether target processes inherited proxy env.

4. Run focused follow-up probes only when needed:
   - `curl -x http://127.0.0.1:<port> ...` for local proxy.
   - `curl -x http://<wsl-gateway>:<port> ...` when `127.0.0.1` fails from WSL.
   - `tr '\0' '\n' < /proc/<pid>/environ | rg -i 'proxy'` for tmux/systemd/app env.
   - Clash/Mihomo logs for `timeout`, `dns`, `tun`, `bind6`, `provider`, or `rule` evidence.

## Safe Fix Patterns

### WSL shell proxy

To print WSL exports without editing files:

```bash
bash /home/zhanxp/projects/myagent/skills/skills-local/clash-proxy/scripts/print_wsl_proxy_exports.sh
```

Use the printed exports temporarily first. Append to `~/.bashrc`, `~/.zshrc`, or profile files only when the user asks for persistent setup, and back up the target file first.

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
