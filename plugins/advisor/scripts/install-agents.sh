#!/bin/sh
# Install the exact consultation role and recoverably retire known historical roles.

set -eu

usage() {
  cat <<'EOF'
Usage: install-agents.sh [--target-dir PATH] [--check]

Install only advisor-terra.toml and advisor-sol.toml. Byte-exact known historical
implementation/review roles are renamed to <role>.toml.retired-v0.6.0, the historical
Sol consultation role to sol-advisor.toml.retired-v1.0.0, and the obsolete neutral
Advisor role to advisor.toml.retired-v1.0.1. Every path is preflighted before mutation.
Known exact Advisor 1.1.0 and prior 1.3.0 role files are renamed to generation-specific
retirement paths before the current roles are installed.
The script never edits Codex configuration.
EOF
}

fail() { printf '%s\n' "ERROR: $*" >&2; exit 1; }
path_exists() { [ -e "$1" ] || [ -L "$1" ]; }
digest() { shasum -a 256 "$1" 2>/dev/null | awk 'NF {print $1; exit}'; }
known_digest() {
  candidate=$1
  shift
  for expected in "$@"; do [ "$candidate" = "$expected" ] && return 0; done
  return 1
}

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
terra_template=$script_dir/../agents/advisor-terra.toml
sol_template=$script_dir/../agents/advisor-sol.toml
for template in "$terra_template" "$sol_template"; do
  [ -f "$template" ] && [ ! -L "$template" ] || fail "shipped advisor role is missing or unsafe: $template"
done

if [ -n "${CODEX_HOME-}" ]; then
  target_dir=$CODEX_HOME/agents
else
  [ -n "${HOME-}" ] || fail "HOME is unset; pass --target-dir."
  target_dir=$HOME/.codex/agents
fi
check_only=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target-dir)
      [ "$#" -ge 2 ] && [ -n "$2" ] || fail "--target-dir requires a non-empty path."
      case "$2" in --*) fail "option-like target paths must be prefixed with ./" ;; esac
      target_dir=$2
      shift 2
      ;;
    --check) check_only=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
case "$target_dir" in /*) ;; *) target_dir=$(pwd -P)/$target_dir ;; esac
case "$target_dir" in /|//) fail "refusing filesystem root as target" ;; esac

terra_current=$target_dir/advisor-terra.toml
sol_current=$target_dir/advisor-sol.toml
terra_current_retired=$terra_current.retired-v1.1.0
sol_current_retired=$sol_current.retired-v1.1.0
terra_v130_retired=$terra_current.retired-v1.3.0
sol_v130_retired=$sol_current.retired-v1.3.0
neutral_advisor=$target_dir/advisor.toml
legacy_advisor=$target_dir/sol-advisor.toml
luna=$target_dir/sol-advisor-luna-implementer.toml
terra=$target_dir/sol-advisor-terra-implementer.toml
reviewer=$target_dir/sol-advisor-sol-reviewer.toml
luna_retired=$luna.retired-v0.6.0
terra_retired=$terra.retired-v0.6.0
reviewer_retired=$reviewer.retired-v0.6.0
legacy_advisor_retired=$legacy_advisor.retired-v1.0.0
neutral_advisor_retired=$neutral_advisor.retired-v1.0.1

# Immutable byte identities from v0.2.0, v0.3-v0.4/intermediate v0.5,
# v0.5.0, and v0.6.0. Unknown content always fails closed.
luna_v020=fba1b42849d93737e83b094a2ab0b1611f87ac37db7438c8bbdf581f0813f8eb
luna_v050=5cfaf77f14757074ca5d3cfecd0b8204c91dc14eff8d6119985c64416ddf4853
luna_v060=12fa9180a292876e6731bc325779123bcd931c3caa902fbf90d676a31833be84
terra_v020=4425a8c1f21ce8c6af93f96adc253bbc33ea301f1389b3fa8ce350be08584eca
terra_v050=dc329fe87f6f6610c13157ec16432f91c79cf5a541ee3e7448f6afb165dd18ce
terra_intermediate=06c318e5e93f37452635906394e6ea69fb6a65ba9e6ad7172d37b444e0dc871d
terra_v060=77ed2f36bb149da5d9032230c3d6f5e5cd56b059b3fa5f59085249bba06e1f3a
reviewer_v060=0333acf0ef562bcfebd06009ac09bd1dd8cbc04c4cf28e08e9e049bd8bf202d2
legacy_advisor_v100=20ed49d92068594b251b2cf3fc38207f415a39879e15d07d635b3f7f7127da57
neutral_advisor_v101=b0be4d07ef2958ad2dd01a4b11be6edff309063fe45d75e778aeac6dfce80363
terra_advisor_v110=95be7e69ee4d5350ea199a66280e180774309371fefcf1a2765f782ec1a670c0
sol_advisor_v110=5ab78b10e1abd4b86d8adeb7d71aa6b4d1c79b1a44457d2c717f5a03cd360367
terra_advisor_v130=4ad79cb613cc9865cb3d1db02f2e98b3b117524153c075a2de3d6bd249798c5e
sol_advisor_v130=4c29a9fec188e7c9c1618dacbcf0e26e40781f1ba783f425ece24c5919a16ad4

classify_current() {
  template=$1 current=$2 retired_v110=$3 digest_v110=$4 retired_v130=$5 digest_v130=$6
  for record in "$retired_v110:$digest_v110" "$retired_v130:$digest_v130"; do
    retired=${record%%:*}; expected=${record#*:}
    if path_exists "$retired"; then
      if [ -L "$retired" ] || [ ! -f "$retired" ]; then printf '%s\n' unsafe-retired; return
      elif [ "$(digest "$retired")" != "$expected" ]; then printf '%s\n' conflict-retired; return
      fi
    fi
  done
  if path_exists "$current"; then
    if [ -L "$current" ] || [ ! -f "$current" ]; then printf '%s\n' unsafe; return
    elif cmp -s "$template" "$current"; then printf '%s\n' current; return
    fi
    value=$(digest "$current")
    if [ "$value" = "$digest_v110" ] && ! path_exists "$retired_v110"; then printf '%s\n' active-known-v110; return
    elif [ "$value" = "$digest_v130" ] && ! path_exists "$retired_v130"; then printf '%s\n' active-known-v130; return
    elif [ "$value" = "$digest_v110" ] || [ "$value" = "$digest_v130" ]; then printf '%s\n' dual; return
    else printf '%s\n' conflict; return
    fi
  fi
  if path_exists "$retired_v110" || path_exists "$retired_v130"; then printf '%s\n' retired-known
  else printf '%s\n' missing
  fi
}

classify_history() {
  active=$1 retired=$2
  shift 2
  if path_exists "$active" && path_exists "$retired"; then printf '%s\n' dual; return; fi
  if path_exists "$active"; then
    if [ -L "$active" ] || [ ! -f "$active" ]; then printf '%s\n' unsafe-active; return; fi
    value=$(digest "$active")
    if known_digest "$value" "$@"; then printf '%s\n' active-known; else printf '%s\n' active-unknown; fi
    return
  fi
  if path_exists "$retired"; then
    if [ -L "$retired" ] || [ ! -f "$retired" ]; then printf '%s\n' unsafe-retired; return; fi
    value=$(digest "$retired")
    if known_digest "$value" "$@"; then printf '%s\n' retired-known; else printf '%s\n' retired-conflict; fi
    return
  fi
  printf '%s\n' absent
}

terra_current_state=$(classify_current "$terra_template" "$terra_current" "$terra_current_retired" "$terra_advisor_v110" "$terra_v130_retired" "$terra_advisor_v130")
sol_current_state=$(classify_current "$sol_template" "$sol_current" "$sol_current_retired" "$sol_advisor_v110" "$sol_v130_retired" "$sol_advisor_v130")
luna_state=$(classify_history "$luna" "$luna_retired" "$luna_v020" "$luna_v050" "$luna_v060")
terra_state=$(classify_history "$terra" "$terra_retired" "$terra_v020" "$terra_v050" "$terra_intermediate" "$terra_v060")
reviewer_state=$(classify_history "$reviewer" "$reviewer_retired" "$reviewer_v060")
legacy_advisor_state=$(classify_history "$legacy_advisor" "$legacy_advisor_retired" "$legacy_advisor_v100")
neutral_advisor_state=$(classify_history "$neutral_advisor" "$neutral_advisor_retired" "$neutral_advisor_v101")

if path_exists "$target_dir" && { [ -L "$target_dir" ] || [ ! -d "$target_dir" ]; }; then
  fail "target is not a real directory: $target_dir"
fi
case "$terra_current_state" in current|missing|active-known-v110|active-known-v130|retired-known) ;; *) fail "Terra advisor destination is $terra_current_state: $terra_current" ;; esac
case "$sol_current_state" in current|missing|active-known-v110|active-known-v130|retired-known) ;; *) fail "Sol advisor destination is $sol_current_state: $sol_current" ;; esac
for record in "Luna:$luna_state" "Terra:$terra_state" "reviewer:$reviewer_state" "legacy advisor:$legacy_advisor_state" "neutral advisor:$neutral_advisor_state"; do
  label=${record%%:*}; state=${record#*:}
  case "$state" in absent|retired-known) ;;
    active-known) [ "$check_only" -eq 0 ] || fail "$label historical role is still active" ;;
    *) fail "$label historical state is $state; refusing all mutation" ;;
  esac
done

if [ "$check_only" -eq 1 ]; then
  [ "$terra_current_state" = current ] || fail "Terra advisor is not installed exactly"
  [ "$sol_current_state" = current ] || fail "Sol advisor is not installed exactly"
  printf '%s\n' "CHECK PASSED: exact Terra and Sol advisors installed; known historical roles inactive."
  exit 0
fi

[ -d "$target_dir" ] || mkdir -p "$target_dir" || fail "could not create target directory"
[ -d "$target_dir" ] && [ ! -L "$target_dir" ] || fail "target changed after preflight"

# Revalidate every path before the first mutation.
[ "$(classify_current "$terra_template" "$terra_current" "$terra_current_retired" "$terra_advisor_v110" "$terra_v130_retired" "$terra_advisor_v130")" = "$terra_current_state" ] || fail "Terra advisor state changed after preflight"
[ "$(classify_current "$sol_template" "$sol_current" "$sol_current_retired" "$sol_advisor_v110" "$sol_v130_retired" "$sol_advisor_v130")" = "$sol_current_state" ] || fail "Sol advisor state changed after preflight"
[ "$(classify_history "$luna" "$luna_retired" "$luna_v020" "$luna_v050" "$luna_v060")" = "$luna_state" ] || fail "Luna state changed after preflight"
[ "$(classify_history "$terra" "$terra_retired" "$terra_v020" "$terra_v050" "$terra_intermediate" "$terra_v060")" = "$terra_state" ] || fail "Terra state changed after preflight"
[ "$(classify_history "$reviewer" "$reviewer_retired" "$reviewer_v060")" = "$reviewer_state" ] || fail "reviewer state changed after preflight"
[ "$(classify_history "$legacy_advisor" "$legacy_advisor_retired" "$legacy_advisor_v100")" = "$legacy_advisor_state" ] || fail "legacy advisor state changed after preflight"
[ "$(classify_history "$neutral_advisor" "$neutral_advisor_retired" "$neutral_advisor_v101")" = "$neutral_advisor_state" ] || fail "neutral advisor state changed after preflight"

retire_one() {
  label=$1 active=$2 retired=$3 state=$4
  [ "$state" = active-known ] || return 0
  [ -f "$active" ] && [ ! -L "$active" ] && ! path_exists "$retired" || fail "$label retirement path changed"
  mv "$active" "$retired" || fail "could not retire $label role"
  printf '%s\n' "RETIRED: $active -> $retired"
}
retire_one Luna "$luna" "$luna_retired" "$luna_state"
retire_one Terra "$terra" "$terra_retired" "$terra_state"
retire_one reviewer "$reviewer" "$reviewer_retired" "$reviewer_state"
retire_one "legacy advisor" "$legacy_advisor" "$legacy_advisor_retired" "$legacy_advisor_state"
retire_one "neutral advisor" "$neutral_advisor" "$neutral_advisor_retired" "$neutral_advisor_state"

retire_upgrade() {
  label=$1 active=$2 retired=$3 state=$4 expected_state=$5 old_digest=$6
  [ "$state" = "$expected_state" ] || return 0
  [ -f "$active" ] && [ ! -L "$active" ] && [ "$(digest "$active")" = "$old_digest" ] && ! path_exists "$retired" || fail "$label 1.1.0 retirement path changed"
  mv "$active" "$retired" || fail "could not retire $label 1.1.0 role"
  printf '%s\n' "RETIRED: $active -> $retired"
}
retire_upgrade Terra "$terra_current" "$terra_current_retired" "$terra_current_state" active-known-v110 "$terra_advisor_v110"
retire_upgrade Sol "$sol_current" "$sol_current_retired" "$sol_current_state" active-known-v110 "$sol_advisor_v110"
retire_upgrade Terra "$terra_current" "$terra_v130_retired" "$terra_current_state" active-known-v130 "$terra_advisor_v130"
retire_upgrade Sol "$sol_current" "$sol_v130_retired" "$sol_current_state" active-known-v130 "$sol_advisor_v130"

install_one() {
  label=$1 template=$2 current=$3 state=$4
  case "$state" in missing|active-known-v110|active-known-v130|retired-known) install_required=1 ;; *) install_required=0 ;; esac
  if [ "$install_required" -eq 1 ]; then
    staged=$(mktemp "$target_dir/.advisor.XXXXXX") || fail "could not stage $label advisor role"
    trap 'rm -f "$staged"' 0 HUP INT TERM
    cp "$template" "$staged" || fail "could not copy $label advisor role"
    [ ! -e "$current" ] && [ ! -L "$current" ] || fail "$label advisor destination appeared during install"
    ln "$staged" "$current" || fail "$label advisor destination appeared during install"
    rm -f "$staged"
    trap - 0 HUP INT TERM
    printf '%s\n' "INSTALLED: $current"
  else
    printf '%s\n' "ALREADY CURRENT: $current"
  fi
}
install_one Terra "$terra_template" "$terra_current" "$terra_current_state"
install_one Sol "$sol_template" "$sol_current" "$sol_current_state"

sh "$0" --target-dir "$target_dir" --check >/dev/null
printf '%s\n' "INSTALL PASSED: consultation roles exact; historical roles inactive."
