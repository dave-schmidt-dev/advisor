#!/bin/sh
# Advisor configuration entrypoint. State is always owned by the Codex host.

set -eu
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' 'ADVISOR CONFIG: python3 is unavailable' >&2
  exit 2
fi
for helper in advisor_config.py advisor_state.py advisor_catalog.py advisor_settings.py advisor_journal.py advisor_discovery.py advisor_canary.py advisor_doctor.py advisor_process.py; do
  if [ ! -f "$script_dir/$helper" ] || [ -L "$script_dir/$helper" ]; then
    printf '%s\n' "ADVISOR CONFIG: installed Advisor helper is unsafe ($helper)" >&2
    exit 2
  fi
done
exec python3 "$script_dir/advisor_config.py" "$@"
