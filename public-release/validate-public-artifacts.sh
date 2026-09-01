#!/bin/sh
# Non-networked validation for the public Codex Advisor candidate artifacts.

set -eu

pass() { printf '%s\n' "PASS: $*"; }
fail() { printf '%s\n' "FAIL: $*" >&2; exit 1; }

case "$#" in
  0) fail "expected --candidate, --allow-legacy-companions, or one or more paths" ;;
  1)
    case "$1" in
      --candidate|--allow-legacy-companions) mode=$1 ;;
      -*) fail "unknown flag: $1" ;;
      *) mode=paths ;;
    esac
    ;;
  *)
    for argument in "$@"; do
      case "$argument" in
        --candidate|--allow-legacy-companions) fail "cannot mix flags and positional paths" ;;
        -*) fail "unknown flag: $argument" ;;
      esac
    done
    mode=paths
    ;;
esac

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
repo_dir=$(CDPATH= cd "$script_dir/.." && pwd) || exit 1
plugin_dir=$repo_dir/plugins/advisor
manifest=$plugin_dir/.codex-plugin/plugin.json
marketplace=$repo_dir/.agents/plugins/marketplace.json
skill=$plugin_dir/skills/consultation/SKILL.md
operations=$plugin_dir/skills/consultation/references/operations.md

candidate_contract() {
  [ -f "$manifest" ] || fail "missing manifest: $manifest"
  python3 - "$manifest" >/dev/null 2>&1 <<'PY' || fail "invalid manifest JSON or candidate identity contract"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    manifest = json.load(source)
if manifest.get("name") != "advisor":
    raise SystemExit("unexpected name")
if manifest.get("interface", {}).get("displayName") != "Codex Advisor":
    raise SystemExit("unexpected display name")
if manifest.get("skills") != "./skills/":
    raise SystemExit("unexpected skills path")
for key in ("hooks", "apps", "mcpServers"):
    if key in manifest:
        raise SystemExit("forbidden manifest component: " + key)
PY
  pass "manifest JSON, identity, and skills-only contract"

  [ -f "$marketplace" ] || fail "missing marketplace entry: $marketplace"
  python3 - "$marketplace" >/dev/null 2>&1 <<'PY' || fail "invalid marketplace JSON or marketplace declares a forbidden component"
import json
import sys

forbidden = {"hooks", "apps", "mcp", "mcpservers"}

def walk(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in forbidden:
                raise SystemExit("forbidden marketplace component: " + key)
            walk(child)
    elif isinstance(value, list):
        for child in value:
            walk(child)

with open(sys.argv[1], encoding="utf-8") as source:
    walk(json.load(source))
PY
  pass "marketplace declares no MCP, app, or lifecycle-hook component"

  for directory in hooks apps mcp; do
    [ ! -d "$plugin_dir/$directory" ] || fail "forbidden plugin directory: $plugin_dir/$directory"
  done
  pass "plugin has no hooks, apps, or mcp directory"

  skill_count=$(find "$plugin_dir/skills" -type f -name SKILL.md | wc -l | tr -d '[:space:]')
  [ "$skill_count" = 1 ] || fail "expected exactly one SKILL.md under $plugin_dir/skills; found $skill_count"
  [ -f "$skill" ] || fail "missing expected skill: $skill"
  [ -f "$operations" ] || fail "missing expected operations reference: $operations"
  pass "exactly one skill definition is present"

  referenced_scripts=$(awk '
    {
      line = $0
      while (match(line, /scripts\/[A-Za-z0-9._\/-]*\.sh/)) {
        print substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$skill" "$operations" | sort -u)
  for relative_path in $referenced_scripts; do
    [ -f "$plugin_dir/$relative_path" ] || fail "missing referenced script: $plugin_dir/$relative_path"
  done
  pass "all skill and operations script references resolve"

  relative_links=$(awk '
    {
      line = $0
      while (match(line, /\]\([^)]*\)/)) {
        target = substr(line, RSTART + 2, RLENGTH - 3)
        if (target != "") print target
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$skill")
  skill_dir=$(CDPATH= cd "$(dirname "$skill")" && pwd) || exit 1
  for target in $relative_links; do
    case "$target" in
      *://*|mailto:*|/*|\#*) continue ;;
    esac
    target=${target%%\#*}
    target=${target%%\?*}
    [ -n "$target" ] || continue
    [ -f "$skill_dir/$target" ] || [ -d "$skill_dir/$target" ] || fail "missing relative SKILL.md link target: $skill_dir/$target"
  done
  pass "all relative SKILL.md links resolve"
}

# Documentation makes public claims; scripts mention MCP only to forbid it. The
# documentation rule is therefore stricter: any line naming MCP or a hosted service
# must also carry a negation, so an affirmative claim cannot reach the listing.
is_public_document() {
  # Normalize first: a relative path such as `docs/listing.md` has no leading
  # component for `*/docs/` to bind to, so the pattern would silently miss it.
  case "$1" in
    /*) candidate=$1 ;;
    *) candidate=./$1 ;;
  esac
  case "$candidate" in
    */docs/*.md|*/README.md|*/NOTICE.md) return 0 ;;
    *) return 1 ;;
  esac
}

scan_file() {
  file=$1
  # The bracket expression stops this line from matching itself when the
  # validator scans its own source, and widens the check to a lowercase home.
  if grep -E -q '/[Uu]sers/' "$file"; then
    fail "disclosure hazard (absolute home path): $file"
  fi
  if grep -E -q 'sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xoxb-[A-Za-z0-9-]{20,}|BEGIN [A-Z ]*PRIVATE KEY' "$file"; then
    fail "disclosure hazard (credential pattern): $file"
  fi
  if grep -E -i -q '((codex[[:space:]]+advisor|advisor|the[[:space:]]+plugin)[[:space:]]+(runs|is[[:space:]]+running|operates|hosts|provides|starts)[[:space:]]+(as[[:space:]]+)?(an?[[:space:]]+)?(MCP[[:space:]]+server|hosted[[:space:]]+service))' "$file"; then
    fail "disclosure hazard (MCP or hosted-service claim): $file"
  fi
  if is_public_document "$file"; then
    unnegated=$(grep -E -i '(MCP|hosted[[:space:]]+service)' "$file" \
      | grep -E -i -v -c '(\bno\b|\bnot\b|\bnever\b|\bwithout\b|unsupported|out of scope|forbidden|reject)' \
      || true)
    [ "${unnegated:-0}" -eq 0 ] || fail "unnegated MCP or hosted-service mention in a public document: $file"
  fi
}

scan_directory() {
  find "$1" -type f -print | while IFS= read -r file; do
    scan_file "$file" || exit 1
  done
}

scan_path() {
  path=$1
  [ -e "$path" ] || fail "named path does not exist: $path"
  if [ -f "$path" ]; then
    scan_file "$path"
  elif [ -d "$path" ]; then
    scan_directory "$path"
  else
    fail "named path is neither a file nor directory: $path"
  fi
}

case "$mode" in
  --candidate)
    candidate_contract
    ;;
  --allow-legacy-companions)
    candidate_contract
    for companion in \
      agents/advisor-terra.toml \
      agents/advisor-sol.toml \
      evals/trigger-cases.json \
      scripts/install-agents.sh; do
      [ -f "$plugin_dir/$companion" ] || fail "missing permitted source-validation companion: $plugin_dir/$companion"
      pass "permitted source-validation companion: plugins/advisor/$companion"
    done
    for artifact in "$repo_dir/README.md" "$repo_dir/NOTICE.md" "$repo_dir/LICENSE" "$repo_dir/docs" "$plugin_dir"; do
      scan_path "$artifact"
    done
    pass "public artifact disclosure scan"
    ;;
  paths)
    for path in "$@"; do
      scan_path "$path"
    done
    pass "disclosure scan passed for named paths"
    ;;
esac
