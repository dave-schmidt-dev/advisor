#!/bin/sh
# Advisor configuration entrypoint. State is always owned by the Codex host.

set -eu
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' 'ADVISOR CONFIG: python3 is unavailable' >&2
  exit 2
fi
exec python3 "$script_dir/advisor_config.py" "$@"
