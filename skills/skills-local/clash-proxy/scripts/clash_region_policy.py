#!/usr/bin/env python3
"""Apply or preview a Clash Verge US-first/Japan-fallback/no-Hong-Kong policy."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

import yaml


ROOT_CANDIDATES = [
    "AppData/Roaming/io.github.clash-verge-rev.clash-verge-rev",
    "AppData/Roaming/Clash Verge",
    ".config/mihomo",
    ".config/clash",
]

DIRECT_TARGETS = {"DIRECT", "REJECT", "REJECT-DROP", "PASS"}
DEFAULT_TEST_URL = "https://www.gstatic.com/generate_204"

JS_TEMPLATE = """// Define main function (script entry)

function main(config, profileName) {
  const usAuto = "__PRIMARY_GROUP__";
  const jpAuto = "__FALLBACK_GROUP__";
  const fallback = "__CHAIN_GROUP__";
  const testUrl = "__TEST_URL__";

  const hkPattern = /__BAN_PATTERN__/i;
  const usPattern = /__PRIMARY_PATTERN__/i;
  const jpPattern = /__FALLBACK_PATTERN__/i;
  const directTargets = new Set(["DIRECT", "REJECT", "REJECT-DROP", "PASS"]);

  function isNamedProxy(item) {
    return item && typeof item.name === "string";
  }

  function proxyNamesByPattern(pattern) {
    const proxies = Array.isArray(config.proxies) ? config.proxies : [];
    return proxies
      .filter(isNamedProxy)
      .map((proxy) => proxy.name)
      .filter((name) => pattern.test(name) && !hkPattern.test(name));
  }

  function withoutBanned(names) {
    return (Array.isArray(names) ? names : []).filter((name) => !hkPattern.test(String(name)));
  }

  function rewriteRule(rule) {
    if (typeof rule !== "string") return rule;

    const parts = rule.split(",");
    if (parts.length < 2) return rule;

    if (parts[0] === "MATCH") {
      if (!directTargets.has(parts[1])) parts[1] = fallback;
      return parts.join(",");
    }

    if (parts.length >= 3 && !directTargets.has(parts[2])) {
      parts[2] = fallback;
    }
    return parts.join(",");
  }

  const primaryNodes = proxyNamesByPattern(usPattern);
  const fallbackNodes = proxyNamesByPattern(jpPattern);
  if (primaryNodes.length === 0 || fallbackNodes.length === 0) {
    return config;
  }

  config.proxies = (Array.isArray(config.proxies) ? config.proxies : [])
    .filter((proxy) => !isNamedProxy(proxy) || !hkPattern.test(proxy.name));

  const existingGroups = (Array.isArray(config["proxy-groups"]) ? config["proxy-groups"] : [])
    .filter((group) => group && typeof group.name === "string")
    .filter((group) => !hkPattern.test(group.name))
    .filter((group) => ![usAuto, jpAuto, fallback].includes(group.name))
    .map((group) => {
      const next = Object.assign({}, group);
      next.proxies = withoutBanned(next.proxies);

      if (["SSRDOG", "Auto", "Google", "OpenAI", "Telegram"].includes(next.name)) {
        next.type = next.name === "Auto" ? "fallback" : "select";
        next.proxies = [fallback];
        next.url = testUrl;
        next.interval = 300;
      }

      return next;
    });

  config["proxy-groups"] = [
    {
      name: usAuto,
      type: "url-test",
      proxies: primaryNodes,
      url: testUrl,
      interval: 300,
      tolerance: 50,
    },
    {
      name: jpAuto,
      type: "url-test",
      proxies: fallbackNodes,
      url: testUrl,
      interval: 300,
      tolerance: 50,
    },
    {
      name: fallback,
      type: "fallback",
      proxies: [usAuto, jpAuto],
      url: testUrl,
      interval: 300,
    },
  ].concat(existingGroups);

  config.rules = (Array.isArray(config.rules) ? config.rules : []).map(rewriteRule);

  return config;
}
"""


def load_yaml(path: Path) -> Any:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def write_yaml(path: Path, data: Any) -> None:
    path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")


def find_root() -> Path:
    for user_dir in Path("/mnt/c/Users").glob("*"):
        if user_dir.name in {"All Users", "Default", "Default User", "Public"}:
            continue
        for suffix in ROOT_CANDIDATES:
            candidate = user_dir / suffix
            if (candidate / "profiles.yaml").exists() or (candidate / "clash-verge.yaml").exists():
                return candidate
    raise SystemExit("Could not locate a Clash/Mihomo config root under /mnt/c/Users")


def backup(path: Path, tag: str) -> Path:
    backup_dir = path.parent.parent / "codex-backups" if path.parent.name == "profiles" else path.parent / "codex-backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    destination = backup_dir / f"{path.name}.before-region-policy-{tag}.bak"
    shutil.copy2(path, destination)
    return destination


def names_matching(proxies: list[dict[str, Any]], pattern: re.Pattern[str], banned: re.Pattern[str]) -> list[str]:
    return [
        str(proxy["name"])
        for proxy in proxies
        if isinstance(proxy, dict)
        and isinstance(proxy.get("name"), str)
        and pattern.search(proxy["name"])
        and not banned.search(proxy["name"])
    ]


def rewrite_rule(rule: Any, chain_group: str) -> Any:
    if not isinstance(rule, str):
        return rule
    parts = rule.split(",")
    if len(parts) < 2:
        return rule
    if parts[0] == "MATCH":
        if parts[1] not in DIRECT_TARGETS:
            parts[1] = chain_group
        return ",".join(parts)
    if len(parts) >= 3 and parts[2] not in DIRECT_TARGETS:
        parts[2] = chain_group
    return ",".join(parts)


def transform_config(config: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    primary_re = re.compile(args.primary_pattern, re.I)
    fallback_re = re.compile(args.fallback_pattern, re.I)
    banned_re = re.compile(args.ban_pattern, re.I)

    proxies = [proxy for proxy in config.get("proxies", []) if isinstance(proxy, dict)]
    primary_nodes = names_matching(proxies, primary_re, banned_re)
    fallback_nodes = names_matching(proxies, fallback_re, banned_re)
    if not primary_nodes or not fallback_nodes:
        raise SystemExit(
            f"Need at least one primary and fallback node; found primary={len(primary_nodes)} fallback={len(fallback_nodes)}"
        )

    config = json.loads(json.dumps(config, ensure_ascii=False))
    config["proxies"] = [
        proxy
        for proxy in config.get("proxies", [])
        if not (isinstance(proxy, dict) and isinstance(proxy.get("name"), str) and banned_re.search(proxy["name"]))
    ]

    rebuilt_groups: list[dict[str, Any]] = []
    for group in config.get("proxy-groups", []):
        if not isinstance(group, dict) or not isinstance(group.get("name"), str):
            continue
        name = group["name"]
        if banned_re.search(name) or name in {args.primary_group, args.fallback_group, args.chain_group}:
            continue

        group = dict(group)
        group["proxies"] = [
            item for item in group.get("proxies", []) if not banned_re.search(str(item))
        ]
        if name in {"SSRDOG", "Auto", "Google", "OpenAI", "Telegram"}:
            group["type"] = "fallback" if name == "Auto" else "select"
            group["proxies"] = [args.chain_group]
            group["url"] = args.test_url
            group["interval"] = 300
        rebuilt_groups.append(group)

    config["proxy-groups"] = [
        {
            "name": args.primary_group,
            "type": "url-test",
            "proxies": primary_nodes,
            "url": args.test_url,
            "interval": 300,
            "tolerance": 50,
        },
        {
            "name": args.fallback_group,
            "type": "url-test",
            "proxies": fallback_nodes,
            "url": args.test_url,
            "interval": 300,
            "tolerance": 50,
        },
        {
            "name": args.chain_group,
            "type": "fallback",
            "proxies": [args.primary_group, args.fallback_group],
            "url": args.test_url,
            "interval": 300,
        },
        *rebuilt_groups,
    ]

    config["rules"] = [rewrite_rule(rule, args.chain_group) for rule in config.get("rules", [])]
    return config


def js_regex_source(pattern: str) -> str:
    return pattern.replace("/", r"\/")


def js_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)[1:-1]


def render_js(args: argparse.Namespace) -> str:
    replacements = {
        "__PRIMARY_GROUP__": js_string(args.primary_group),
        "__FALLBACK_GROUP__": js_string(args.fallback_group),
        "__CHAIN_GROUP__": js_string(args.chain_group),
        "__TEST_URL__": js_string(args.test_url),
        "__BAN_PATTERN__": js_regex_source(args.ban_pattern),
        "__PRIMARY_PATTERN__": js_regex_source(args.primary_pattern),
        "__FALLBACK_PATTERN__": js_regex_source(args.fallback_pattern),
    }
    body = JS_TEMPLATE
    for old, new in replacements.items():
        body = body.replace(old, new)
    return body


def active_script_path(root: Path) -> tuple[Path, dict[str, Any]]:
    profiles_path = root / "profiles.yaml"
    profiles = load_yaml(profiles_path)
    current = profiles.get("current")
    active = next((item for item in profiles.get("items", []) if item.get("uid") == current), None)
    if not active:
        raise SystemExit("Could not resolve active profile from profiles.yaml")
    script_uid = (active.get("option") or {}).get("script")
    if not script_uid:
        raise SystemExit("Active profile does not declare an option.script enhancement")
    return root / "profiles" / f"{script_uid}.js", profiles


def update_selected(root: Path, profiles: dict[str, Any], chain_group: str, tag: str) -> Path:
    profiles_path = root / "profiles.yaml"
    backup_path = backup(profiles_path, tag)
    current = profiles.get("current")
    for item in profiles.get("items", []):
        if item.get("uid") != current:
            continue
        selected = item.setdefault("selected", [])
        if selected:
            selected[0]["now"] = chain_group
        else:
            selected.append({"name": item.get("name") or "Proxy", "now": chain_group})
    write_yaml(profiles_path, profiles)
    return backup_path


def summarize(config: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    banned_re = re.compile(args.ban_pattern, re.I)
    proxies = [p.get("name") for p in config.get("proxies", []) if isinstance(p, dict)]
    groups = [g for g in config.get("proxy-groups", []) if isinstance(g, dict)]
    rules = config.get("rules", [])
    return {
        "proxies": len(proxies),
        "banned_proxies": sum(1 for name in proxies if banned_re.search(str(name))),
        "groups": len(groups),
        "banned_groups_or_refs": sum(
            1
            for group in groups
            if banned_re.search(str(group.get("name")))
            or any(banned_re.search(str(item)) for item in group.get("proxies", []))
        ),
        "rules": len(rules),
        "banned_rules": sum(1 for rule in rules if banned_re.search(str(rule))),
        "chain_group_exists": any(group.get("name") == args.chain_group for group in groups),
        "match_rule": next((rule for rule in rules if str(rule).startswith("MATCH,")), ""),
    }


def maybe_windows_path(path: Path, exe: str) -> str:
    if not exe.lower().endswith(".exe"):
        return str(path)
    result = subprocess.run(
        ["wslpath", "-w", str(path)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


def validate_config(config: dict[str, Any], root: Path, exe: str, tag: str) -> None:
    temp_dir = root / "codex-backups"
    temp_dir.mkdir(parents=True, exist_ok=True)
    temp_path = temp_dir / f"region-policy-validate-{tag}.yaml"
    write_yaml(temp_path, config)
    try:
        result = subprocess.run(
            [exe, "-t", "-d", maybe_windows_path(root, exe), "-f", maybe_windows_path(temp_path, exe)],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        print(result.stdout.strip())
        if result.returncode != 0:
            raise SystemExit(result.returncode)
    finally:
        temp_path.unlink(missing_ok=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, help="Clash Verge config root")
    parser.add_argument("--config", default="clash-verge.yaml", help="Runtime config filename under root")
    parser.add_argument("--primary-pattern", default=r"United States|USA|America|美国|美國|🇺🇸")
    parser.add_argument("--fallback-pattern", default=r"Japan|日本|🇯🇵")
    parser.add_argument("--ban-pattern", default=r"Hong Kong|香港|🇭🇰")
    parser.add_argument("--primary-group", default="US Auto")
    parser.add_argument("--fallback-group", default="Japan Auto")
    parser.add_argument("--chain-group", default="US-Japan-Fallback")
    parser.add_argument("--test-url", default=DEFAULT_TEST_URL)
    parser.add_argument("--write-profile-script", action="store_true")
    parser.add_argument("--update-selected", action="store_true")
    parser.add_argument("--apply-runtime", action="store_true")
    parser.add_argument("--validate-exe", help="Path to verge-mihomo.exe or mihomo")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    root = args.root or find_root()
    config_path = root / args.config
    tag = datetime.now().strftime("%Y%m%d-%H%M%S")

    original = load_yaml(config_path)
    transformed = transform_config(original, args)
    print("root", root)
    print("before", json.dumps(summarize(original, args), ensure_ascii=False))
    print("after", json.dumps(summarize(transformed, args), ensure_ascii=False))

    if args.write_profile_script:
        script_path, profiles = active_script_path(root)
        if script_path.exists():
            print("backup", backup(script_path, tag))
        script_path.write_text(render_js(args), encoding="utf-8")
        print("wrote", script_path)
        if args.update_selected:
            print("backup", update_selected(root, profiles, args.chain_group, tag))
            print("updated", root / "profiles.yaml")
    elif args.update_selected:
        raise SystemExit("--update-selected requires --write-profile-script")

    if args.apply_runtime:
        print("backup", backup(config_path, tag))
        write_yaml(config_path, transformed)
        check_path = root / "clash-verge-check.yaml"
        if check_path.exists():
            print("backup", backup(check_path, tag))
            write_yaml(check_path, transformed)
        print("wrote", config_path)

    if args.validate_exe:
        validate_config(transformed, root, args.validate_exe, tag)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
