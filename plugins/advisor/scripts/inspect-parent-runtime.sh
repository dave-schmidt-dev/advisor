#!/bin/sh
# Emit only allowlisted isolation evidence for the current Codex parent thread.

set -eu

unavailable() {
  printf '%s\n' '{"status":"unavailable","reason_type":"parent_runtime_unavailable","redacted":true}'
  exit 0
}

sessions_dir=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --sessions-dir)
      [ "$#" -ge 2 ] && [ -n "$2" ] || unavailable
      sessions_dir=$2
      shift 2
      ;;
    *) unavailable ;;
  esac
done

parent_thread_id=${CODEX_THREAD_ID-}
printf '%s\n' "$parent_thread_id" | LC_ALL=C grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || unavailable

if [ -z "$sessions_dir" ]; then
  if [ -n "${CODEX_HOME-}" ]; then
    sessions_dir=$CODEX_HOME/sessions
  elif [ -n "${HOME-}" ]; then
    sessions_dir=$HOME/.codex/sessions
  else
    unavailable
  fi
fi

[ -d "$sessions_dir" ] && [ ! -L "$sessions_dir" ] || unavailable

matches=$(find "$sessions_dir" -name "rollout-*-$parent_thread_id.jsonl" -print 2>/dev/null) || unavailable
match_count=$(printf '%s\n' "$matches" | awk 'NF { count += 1 } END { print count + 0 }')
[ "$match_count" -eq 1 ] || unavailable
rollout=$matches
[ -f "$rollout" ] && [ ! -L "$rollout" ] || unavailable

jq -ce -s --arg id "$parent_thread_id" '
  [ .[] | select(.type == "session_meta") | .payload | { id } ] as $metadata |
  [ .[] | select(.type == "turn_context") |
    .payload | {
      sandbox_policy_type: .sandbox_policy.type,
      permission_profile_type: .permission_profile.type
    }
  ] as $contexts |
  if ($metadata | length) != 1 or $metadata[0].id != $id or
     ($contexts | length) == 0
  then error("unavailable")
  else
    [ $contexts[].sandbox_policy_type ] as $sandboxes |
    [ $contexts[].permission_profile_type ] as $permissions |
    if ($sandboxes | unique | length) != 1 or
       ($sandboxes[0] | IN("read-only", "workspace-write") | not) or
       ($permissions | unique | length) != 1 or
       any($permissions[]; type != "string" or length == 0)
    then error("unavailable")
    else {
      status: "available",
      thread_id: $metadata[0].id,
      sandbox_policy_type: $sandboxes[0],
      permission_profile_type: $permissions[0]
    }
    end
  end
' "$rollout" 2>/dev/null || unavailable
