#!/bin/sh
# Non-networked repository verification for the consultation-only plugin.

set -eu
pass() { printf '%s\n' "PASS: $*"; }
fail() { printf '%s\n' "FAIL: $*" >&2; exit 1; }
case "$#" in 0) ;; 1) [ "$1" = --static ] || fail "expected no args or --static" ;; *) fail "expected no args or --static" ;; esac

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
plugin_dir=$(CDPATH= cd "$script_dir/.." && pwd) || exit 1
repo_dir=$(CDPATH= cd "$plugin_dir/../.." && pwd) || exit 1
manifest=$plugin_dir/.codex-plugin/plugin.json
marketplace=$repo_dir/.agents/plugins/marketplace.json
terra_role=$plugin_dir/agents/advisor-terra.toml
sol_role=$plugin_dir/agents/advisor-sol.toml
astra_role=$plugin_dir/agents/advisor-astra.toml
skill=$plugin_dir/skills/consultation/SKILL.md
ui=$plugin_dir/skills/consultation/agents/openai.yaml
operations=$plugin_dir/skills/consultation/references/operations.md
fixtures=$plugin_dir/evals/trigger-cases.json
installer=$script_dir/install-agents.sh
inspector=$script_dir/inspect-agent-runtime.sh
parent_inspector=$script_dir/inspect-parent-runtime.sh
transport=$script_dir/run-advisor.sh
response_schema=$plugin_dir/advisor-response.schema.json
audit=$script_dir/advisor-audit.sh
evaluator=$script_dir/evaluate-triggers.sh
config_test=$plugin_dir/tests/test_advisor_config.py
transport_test=$plugin_dir/tests/test_advisor_transport.py
usage_test=$plugin_dir/tests/test_advisor_usage.py
cli_test=$plugin_dir/tests/test_advisor_cli.py
process_helper=$script_dir/advisor_process.py
config_helper=$script_dir/advisor_config.py
config_wrapper=$script_dir/advisor-config.sh
live_config=$plugin_dir/advisor.toml
models=$plugin_dir/models.json
settings_schema=$plugin_dir/settings.schema.json
readme=$repo_dir/README.md
notice=$repo_dir/NOTICE.md
license=$repo_dir/LICENSE
compat_doc=$repo_dir/docs/public-directory-compatibility.md
model_doc=$repo_dir/docs/model-configuration.md
walkthrough=$repo_dir/docs/advisor-1.4-walkthrough.md
release_notes=$repo_dir/docs/release-notes-draft.md
package_test=$repo_dir/public-release/test_candidate_package.py
verify_dir=$repo_dir/tests/verify

for file in "$manifest" "$marketplace" "$terra_role" "$sol_role" "$astra_role" "$skill" "$ui" "$operations" "$fixtures" "$installer" "$inspector" "$parent_inspector" "$transport" "$response_schema" "$audit" "$evaluator" "$config_test" "$transport_test" "$usage_test" "$cli_test" "$process_helper" "$config_helper" "$script_dir/advisor_state.py" "$script_dir/advisor_catalog.py" "$script_dir/advisor_settings.py" "$script_dir/advisor_journal.py" "$script_dir/advisor_discovery.py" "$script_dir/advisor_canary.py" "$script_dir/advisor_doctor.py" "$config_wrapper" "$live_config" "$models" "$settings_schema" "$model_doc" "$walkthrough" "$release_notes" "$package_test" "$readme" "$notice" "$license" "$plugin_dir/LICENSE" "$plugin_dir/NOTICE.md" "$verify_dir/contract-docs.sh" "$verify_dir/installer.sh" "$verify_dir/inspectors.sh" "$verify_dir/transport.sh" "$verify_dir/audit.sh" "$verify_dir/evaluator.sh" "$verify_dir/release-docs.sh"; do
  [ -f "$file" ] || fail "missing required file: $file"
done
[ "$(find "$plugin_dir/agents" -maxdepth 1 -type f -name '*.toml' | wc -l | tr -d ' ')" -eq 3 ] || fail "expected exactly three active roles"
[ "$(find "$plugin_dir/skills" -type f -name SKILL.md | wc -l | tr -d ' ')" -eq 1 ] || fail "expected exactly one skill"
pass "required inventory: one skill, three model pins including explicit opt-in Astra, read-only transport, parent/child inspectors, evaluator, documentation"

. "$verify_dir/contract-docs.sh"

tmp_base=${TMPDIR:-/tmp}; case "$tmp_base" in /*) ;; *) tmp_base=/tmp ;; esac
tmp=$(mktemp -d "$tmp_base/advisor-verify.XXXXXX") || fail "cannot create fixture directory"
cleanup() { case "$tmp" in "$tmp_base"/advisor-verify.*) rm -rf "$tmp" ;; esac; }
trap cleanup 0 HUP INT TERM
snapshot() { find "$1" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort | while IFS= read -r f; do if [ -L "$f" ]; then printf 'L %s\n' "$(basename "$f")"; elif [ -f "$f" ]; then shasum -a 256 "$f"; else printf 'O %s\n' "$(basename "$f")"; fi; done; }

. "$verify_dir/installer.sh"

. "$verify_dir/inspectors.sh"

. "$verify_dir/transport.sh"

. "$verify_dir/audit.sh"

. "$verify_dir/evaluator.sh"

. "$verify_dir/release-docs.sh"

python3 -m unittest discover -s "$plugin_dir/tests" -p 'test_advisor_*.py'
python3 -m unittest "$package_test"
pass "Advisor behavior tests and candidate packaging tests"

sh -n "$script_dir"/*.sh
[ "$(stat -f '%Lp' "$parent_inspector" 2>/dev/null || stat -c '%a' "$parent_inspector")" = 644 ] || fail "parent inspector must remain mode 100644"
pass "all shell syntax and stderr-progress contract"
printf '%s\n' "VERIFY PASSED: Advisor 1.4.9 consultation-only static contract"
