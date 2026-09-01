#!/bin/sh
# Guide an owner through the attended clean-host smoke receipt flow.
# This script initiates owner-controlled sign-in, never handles credentials,
# runs no consultation itself, and never removes CODEX_HOME.

set -eu
umask 077

# Do not add commands from this flow to the caller's shell history.
unset HISTFILE 2>/dev/null || true
set +o history 2>/dev/null || true

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
verify_script=$repo_root/public-release/verify-clean-host.sh
receipt_path=$repo_root/docs/clean-host-smoke-receipt.json
manifest_source=$repo_root/plugins/advisor/.codex-plugin/plugin.json

codex_home=''
scratch_dir=''
temp_root=${TMPDIR:-/private/tmp}
case "$temp_root" in
  /) ;;
  */) temp_root=${temp_root%/} ;;
esac

usage() {
  printf '%s\n' \
    "Usage: sh public-release/run-clean-host-receipt.sh" \
    "       sh public-release/run-clean-host-receipt.sh --help" \
    '' \
    'Guides an owner through a fresh CODEX_HOME install and captures one' \
    'attended runtime receipt. It never removes CODEX_HOME or runs a consultation.'
}

recover() {
  if [ -n "$codex_home" ]; then
    printf '%s\n' "Recovery: the fresh CODEX_HOME was kept at: $codex_home"
    printf '%s\n' "Remove it manually when finished: rm -rf -- '$codex_home'"
  fi
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  recover >&2
  exit 1
}

cleanup() {
  if [ -n "$scratch_dir" ] && [ -d "$scratch_dir" ]; then
    rm -rf -- "$scratch_dir" 2>/dev/null || true
  fi
}

on_signal() {
  cleanup
  recover >&2
  exit 130
}

trap cleanup EXIT
trap on_signal HUP INT TERM

if [ "$#" -gt 0 ]; then
  case "$1" in
    --help|-h)
      [ "$#" -eq 1 ] || fail 'help does not accept additional arguments'
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown argument: $1"
      ;;
  esac
fi

command -v codex >/dev/null 2>&1 || fail 'codex is required and was not found in PATH'
command -v jq >/dev/null 2>&1 || fail 'jq is required and was not found in PATH'
command -v git >/dev/null 2>&1 || fail 'git is required and was not found in PATH'
[ -f "$verify_script" ] || fail "missing verifier: $verify_script"
[ -d "$repo_root/docs" ] || fail "missing receipt directory: $repo_root/docs"
[ -f "$manifest_source" ] || fail "missing source plugin manifest: $manifest_source"

candidate_ref=$(git -C "$repo_root" rev-parse --verify HEAD) || fail 'failed to resolve local HEAD'
if [ -n "$(git -C "$repo_root" status --short --untracked-files=no)" ]; then
  fail 'tracked tree has uncommitted changes; clean it before running this runbook'
fi
source_manifest_version=$(jq -r '.version // empty' "$manifest_source")
[ -n "$source_manifest_version" ] || fail "source manifest version missing: $manifest_source"

scratch_dir=$(mktemp -d "$temp_root/advisor-clean-host-run.XXXXXX") || fail 'could not create temporary scratch directory'
chmod 700 "$scratch_dir" || fail 'could not protect temporary scratch directory'

printf '%s\n' '── Step 1 of 7: Create and verify a fresh Codex root ──'
codex_home=$(mktemp -d "$temp_root/advisor-clean-host-home.XXXXXX") || fail 'could not create fresh CODEX_HOME'
codex_home=$(CDPATH= cd -- "$codex_home" && pwd -P) || fail 'could not resolve fresh CODEX_HOME'
chmod 700 "$codex_home" || fail 'could not protect fresh CODEX_HOME'
fresh_entries=$(find "$codex_home" -print 2>/dev/null | sed '1d;q') || fail 'could not inspect fresh CODEX_HOME'
[ -z "$fresh_entries" ] || fail 'fresh CODEX_HOME was not empty'
printf '  ✓ Fresh CODEX_HOME: %s\n\n' "$codex_home"

run_codex() {
  CODEX_HOME="$codex_home" codex "$@"
}

printf '%s\n' '── Step 2 of 7: Sign in interactively ──'
printf '%s\n' \
  'Codex will open its interactive browser sign-in flow for this fresh root.' \
  'Complete that flow in your browser; no credential is read or displayed here.'
if ! run_codex login; then
  fail 'Codex login did not complete'
fi
login_status=$scratch_dir/login-status.txt
if ! run_codex login status >"$login_status" 2>&1; then
  fail 'Codex reports this fresh root is not logged in'
fi
if ! grep -Fqx 'Logged in using ChatGPT' "$login_status"; then
  fail 'fresh-root login is not a ChatGPT login'
fi
printf '%s\n\n' '  ✓ Fresh-root ChatGPT login verified.'

printf '%s\n' '── Step 3 of 7: Register the public marketplace ──'
if ! run_codex plugin marketplace add dave-schmidt-dev/advisor --ref "$candidate_ref"; then
  fail 'marketplace registration failed'
fi
printf '%s\n\n' '  ✓ Marketplace registration finished.'

printf '%s\n' '── Step 4 of 7: Install Advisor ──'
if ! run_codex plugin add advisor@advisor; then
  fail 'Advisor installation failed'
fi
printf '%s\n\n' '  ✓ Advisor installation finished.'

printf '%s\n' '── Step 5 of 7: Install the roles from the installed copy ──'
plugin_list=$scratch_dir/plugin-list.json
if ! run_codex plugin list --json >"$plugin_list"; then
  fail 'could not list installed plugins as JSON'
fi
plugin_dir=$(jq -er '
  .installed[]
  | select(.pluginId == "advisor@advisor")
  | .source.path // empty
' "$plugin_list" 2>/dev/null) || fail 'installed Advisor path was not present in plugin list'
[ -n "$plugin_dir" ] && [ "$plugin_dir" != 'null' ] || fail 'installed Advisor path was empty'
[ -d "$plugin_dir" ] || fail "installed Advisor directory does not exist: $plugin_dir"
manifest_installed="$plugin_dir/.codex-plugin/plugin.json"
[ -f "$manifest_installed" ] || fail "installed Advisor manifest does not exist: $manifest_installed"
installed_manifest_version=$(jq -r '.version // empty' "$manifest_installed")
[ -n "$installed_manifest_version" ] || fail "installed manifest version missing: $manifest_installed"
[ "$source_manifest_version" = "$installed_manifest_version" ] || fail "installed manifest version $installed_manifest_version does not match source $source_manifest_version"
install_script=$plugin_dir/scripts/install-agents.sh
[ -f "$install_script" ] || fail "installed Advisor installer does not exist: $install_script"
if ! CODEX_HOME="$codex_home" sh "$install_script"; then
  fail 'installed Advisor role installer failed'
fi
printf '%s\n\n' '  ✓ Installed only the installer from the resolved plugin directory.'

printf '%s\n' '── Step 6 of 7: Run one attended consultation ──'
printf '%s\n' \
  'Start a new Codex session in the fresh root, run exactly one eligible Advisor' \
  'consultation, and save its observed runtime/launcher JSON outside CODEX_HOME.' \
  "Fresh-root command: CODEX_HOME='$codex_home' codex"
printf '%s' 'Press Enter after the consultation and evidence export are complete (EOF continues safely): '
read -r _ || true
printf '%s\n\n' '  ✓ Consultation step acknowledged.'

printf '%s\n' '── Step 7 of 7: Capture the validated receipt ──'
printf '%s\n' 'Enter the path to the observed runtime/launcher JSON.'
printf '%s' 'Evidence path: '
evidence_path=''
read -r evidence_path || true
[ -n "$evidence_path" ] || fail 'evidence path was empty or input ended'
[ -f "$evidence_path" ] || fail "runtime evidence does not exist: $evidence_path"

evidence_dir=$(dirname "$evidence_path")
evidence_name=$(basename "$evidence_path")
evidence_dir_abs=$(CDPATH= cd -- "$evidence_dir" 2>/dev/null && pwd -P) || fail "could not resolve evidence directory: $evidence_dir"
evidence_abs=$evidence_dir_abs/$evidence_name
case "$evidence_abs" in
  "$codex_home"|"$codex_home"/*)
    fail 'evidence must be outside the fresh CODEX_HOME; export a copy elsewhere'
    ;;
esac

thread_id=$(jq -er '
  if (.runtime? | type == "object") then .runtime.thread_id else .thread_id end
' "$evidence_abs") || fail 'evidence did not include a thread_id'
parent_thread_id=$(jq -er '
  if (.runtime? | type == "object") then .runtime.parent_thread_id else .parent_thread_id end
' "$evidence_abs") || fail 'evidence did not include a parent_thread_id'
agent_role=$(jq -er '
  if (.runtime? | type == "object") then .runtime.agent_role else .agent_role end
' "$evidence_abs") || fail 'evidence did not include an agent_role'
model=$(jq -er '
  if (.runtime? | type == "object") then .runtime.model else .model end
' "$evidence_abs") || fail 'evidence did not include a model'
case "$agent_role:$model" in
  advisor-terra:gpt-5.6-terra|advisor-sol:gpt-5.6-sol) ;;
  *) fail 'evidence role/model pair is not allowed for clean-host capture' ;;
esac
printf '%s\n' "$thread_id" | LC_ALL=C grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || fail "thread_id is not a UUID: $thread_id"
printf '%s\n' "$parent_thread_id" | LC_ALL=C grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || fail "parent_thread_id is not a UUID: $parent_thread_id"
[ "$thread_id" != "$parent_thread_id" ] || fail 'thread_id and parent_thread_id must differ'
inspector_script=$plugin_dir/scripts/inspect-agent-runtime.sh
[ -x "$inspector_script" ] || fail "installed runtime inspector missing: $inspector_script"
inspected_runtime=$scratch_dir/inspected-runtime.json
if ! CODEX_HOME="$codex_home" sh "$inspector_script" \
  --sessions-dir "$codex_home/sessions" \
  --expected-role "$agent_role" \
  --expected-model "$model" \
  --expected-parent "$parent_thread_id" \
  "$thread_id" > "$inspected_runtime"; then
  fail 'runtime inspection against the fresh CODEX_HOME failed'
fi
if ! sh "$verify_script" --capture "$receipt_path" "$inspected_runtime"; then
  fail 'receipt validation failed; no valid receipt was accepted'
fi
[ -f "$receipt_path" ] || fail 'verifier reported success but receipt was not present'
printf '%s\n\n' '  ✓ Validated receipt captured.'
printf '%s\n' \
  "Next action: release owner review of $receipt_path; publication remains a separate attended gate."
recover
