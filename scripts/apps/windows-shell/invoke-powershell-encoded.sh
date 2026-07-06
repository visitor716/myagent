#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
exec "$repo_root/skills/skills-local/powershell-skill/scripts/invoke-powershell-encoded.sh" "$@"
