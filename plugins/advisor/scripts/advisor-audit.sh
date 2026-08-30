#!/bin/sh
# Emit a redacted, aggregate-only audit of local advisor session evidence.

set -eu

fail() { printf '%s\n' "ERROR: $*" >&2; exit 1; }
progress() { printf '%s\n' "ADVISOR AUDIT: $*" >&2; }

sessions_dir=''
window_hours=24
since=''
until=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --sessions-dir) [ "$#" -ge 2 ] || fail "--sessions-dir requires DIR"; sessions_dir=$2; shift 2 ;;
    --window-hours) [ "$#" -ge 2 ] || fail "--window-hours requires HOURS"; window_hours=$2; shift 2 ;;
    --since) [ "$#" -ge 2 ] || fail "--since requires an RFC3339 timestamp"; since=$2; shift 2 ;;
    --until) [ "$#" -ge 2 ] || fail "--until requires an RFC3339 timestamp"; until=$2; shift 2 ;;
    --help)
      printf '%s\n' 'usage: advisor-audit.sh [--sessions-dir DIR] [--window-hours HOURS] [--since RFC3339] [--until RFC3339]'
      exit 0
      ;;
    --*) fail "unknown option" ;;
    *) fail "unexpected argument" ;;
  esac
done

if [ -z "$sessions_dir" ]; then
  if [ -n "${CODEX_HOME-}" ]; then sessions_dir=$CODEX_HOME/sessions
  else [ -n "${HOME-}" ] || fail "HOME is unset"; sessions_dir=$HOME/.codex/sessions
  fi
fi
[ -d "$sessions_dir" ] || fail "sessions directory unavailable"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

progress 'session enumeration started'
python3 - "$sessions_dir" "$window_hours" "$since" "$until" <<'PY'
import datetime as dt
import json
import os
import re
import sys

sessions_dir, hours_raw, since_raw, until_raw = sys.argv[1:]

def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)

def parse_time(value):
    if not isinstance(value, str):
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(dt.timezone.utc)

try:
    hours = float(hours_raw)
except ValueError:
    fail("--window-hours must be a positive number")
if hours <= 0:
    fail("--window-hours must be a positive number")

now = dt.datetime.now(dt.timezone.utc)
since = parse_time(since_raw) if since_raw else now - dt.timedelta(hours=hours)
until = parse_time(until_raw) if until_raw else now
if (since_raw and since is None) or (until_raw and until is None):
    fail("--since and --until must be RFC3339 timestamps with a timezone")
if since >= until:
    fail("window start must precede window end")

def iso(value):
    return value.isoformat(timespec="seconds").replace("+00:00", "Z")

def string_at(value, *keys):
    for key in keys:
        if not isinstance(value, dict):
            return None
        value = value.get(key)
    return value if isinstance(value, str) else None

def entry_time(entry):
    for value in (entry.get("timestamp"), string_at(entry, "item", "timestamp"), string_at(entry, "payload", "timestamp")):
        parsed = parse_time(value)
        if parsed is not None:
            return parsed
    return None

def receipt_fields(text, heading, allowed_fields):
    if not isinstance(text, str):
        return {}
    lines = text.splitlines()
    indexes = [index for index, line in enumerate(lines) if line.strip() == heading]
    if len(indexes) != 1:
        return {}
    # Retain only allowlisted receipt fields from this receipt block. Receipt prose
    # and fields after another Advisor heading are never retained or emitted.
    fields = {}
    for line in lines[indexes[0] + 1:]:
        if line.strip() in ("ADVISOR DECISION", "ADVISOR CALL", "ADVISOR RESULT"):
            break
        match = re.fullmatch(r"\s*([a-z_]+)\s*:\s*(\S+)\s*", line)
        if match and match.group(1) in allowed_fields:
            if match.group(1) in fields:
                return {}
            fields[match.group(1)] = match.group(2)
    return fields

def receipt_texts(entry):
    payload = entry.get("payload")
    if entry.get("type") != "response_item" or not isinstance(payload, dict):
        return ()
    if payload.get("type") != "message" or payload.get("role") != "assistant":
        return ()
    content = payload.get("content")
    if not isinstance(content, list):
        return ()
    return tuple(
        item["text"] for item in content
        if isinstance(item, dict) and item.get("type") == "output_text" and isinstance(item.get("text"), str)
    )

def completed_spawn_item(entry):
    """Return an allowlisted completed spawn item from persisted or exported records."""
    payload = entry.get("payload")
    if not isinstance(payload, dict):
        return None
    if entry.get("type") == "event_msg" and payload.get("type") == "item_completed":
        item = payload.get("item")
    elif entry.get("type") == "response_item":
        item = payload
    elif entry.get("type") == "item.completed":
        item = entry.get("item")
    else:
        return None
    if not isinstance(item, dict):
        return None
    if item.get("type") not in ("CollabAgentToolCall", "collab_tool_call"):
        return None
    if item.get("tool") != "spawn_agent" or item.get("status") != "completed":
        return None
    return item

def advisor_spawn_request(entry):
    """Return an advisor role only from a current parent function-call request."""
    payload = entry.get("payload")
    if entry.get("type") != "response_item" or not isinstance(payload, dict):
        return None
    if payload.get("type") != "function_call" or payload.get("name") != "spawn_agent":
        return None
    arguments = payload.get("arguments")
    if not isinstance(arguments, str):
        return None
    try:
        parsed = json.loads(arguments)
    except json.JSONDecodeError:
        return None
    if not isinstance(parsed, dict):
        return None
    role = parsed.get("agent_type")
    return role if role in ("advisor-terra", "advisor-sol") else None

def subagent_activity_item(entry):
    payload = entry.get("payload")
    if entry.get("type") != "event_msg" or not isinstance(payload, dict):
        return None
    if payload.get("type") != "item_completed":
        return None
    item = payload.get("item")
    if not isinstance(item, dict) or item.get("type") != "SubAgentActivity":
        return None
    if item.get("kind") not in ("started", "interacted", "completed", "interrupted"):
        return None
    return item

files = []
try:
    for root, dirs, names in os.walk(sessions_dir):
        dirs.sort()
        for name in sorted(names):
            if name.endswith(".jsonl"):
                files.append(os.path.join(root, name))
except OSError:
    fail("session enumeration unavailable")
print("ADVISOR AUDIT: session parsing started", file=sys.stderr)

# Current SubAgentActivity records do not carry a role. Correlate them only to
# exact current child IDs established independently from full-file session_meta.
advisor_child_ids = set()
for path in files:
    metadata_roles = set()
    metadata_ids = set()
    try:
        with open(path, encoding="utf-8") as handle:
            for raw in handle:
                try:
                    entry = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                if not isinstance(entry, dict) or entry.get("type") != "session_meta":
                    continue
                role = string_at(entry, "payload", "agent_role")
                session_id = string_at(entry, "payload", "id")
                if role is not None:
                    metadata_roles.add(role)
                if session_id is not None:
                    metadata_ids.add(session_id)
    except OSError:
        continue
    if len(metadata_roles) == 1 and metadata_roles.issubset(("advisor-terra", "advisor-sol")) and len(metadata_ids) == 1:
        advisor_child_ids.update(metadata_ids)

attempts = standard = specialist = 0
decision_routes = {"consult": 0, "skip": 0, "unavailable": 0}
decision_evidence = False
child_sessions = {"advisor-terra": 0, "advisor-sol": 0}
parent_spawns = {"advisor-terra": 0, "advisor-sol": 0}
parent_completion_evidence = False
parent_spawn_requests = 0
parent_request_evidence = False
parent_activity = {"started": 0, "interacted": 0, "completed": 0, "interrupted": 0}
parent_activity_evidence = False
stale_underscore = stale_hyphen = 0
completed = unavailable = blocked = accept = modify = reject = 0
sandbox = {"read_only": 0, "workspace_write": 0, "other": 0}
sandbox_evidence = False
tool_calls = 0
tool_evidence = False
durations = []
tokens = {"input": 0, "cached_input": 0, "output": 0, "reasoning": 0}
token_evidence = False
seen_receipts = set()
seen_spawns = set()
seen_child_sessions = set()
seen_requests = set()
seen_activity = set()

for path in files:
    entries = []
    try:
        with open(path, encoding="utf-8") as handle:
            for raw in handle:
                try:
                    entry = json.loads(raw)
                except json.JSONDecodeError:
                    continue
                if isinstance(entry, dict):
                    entries.append(entry)
    except OSError:
        continue
    # Session identity and child role are full-file metadata. Apply the requested
    # window only after extracting them so a child created before the window is
    # still counted when it has activity inside the window.
    session_ids = {
        value for entry in entries
        if entry.get("type") == "session_meta"
        and (value := string_at(entry, "payload", "id")) is not None
    }
    metadata_roles = {
        value for entry in entries
        if entry.get("type") == "session_meta"
        and (value := string_at(entry, "payload", "agent_role")) is not None
    }
    child_roles = metadata_roles.intersection(("advisor-terra", "advisor-sol"))
    child_role = next(iter(child_roles)) if len(child_roles) == 1 and len(metadata_roles) == 1 and len(session_ids) == 1 else None
    in_window = [entry for entry in entries if (stamp := entry_time(entry)) is not None and since <= stamp < until]
    if not in_window:
        continue

    if child_role is not None:
        child_session_id = next(iter(session_ids))
        if child_session_id in seen_child_sessions:
            continue
        seen_child_sessions.add(child_session_id)
        child_sessions[child_role] += 1
        tool_evidence = True
        stamps = [entry_time(entry) for entry in in_window]
        stamps = [stamp for stamp in stamps if stamp is not None]
        if len(stamps) >= 2:
            durations.append(round((max(stamps) - min(stamps)).total_seconds() * 1000))
        sandbox_values = {
            value for entry in in_window
            if (value := string_at(entry, "payload", "sandbox_policy", "type")) is not None
        }
        if sandbox_values:
            sandbox_evidence = True
            if sandbox_values == {"read-only"}: sandbox["read_only"] += 1
            elif sandbox_values == {"workspace-write"}: sandbox["workspace_write"] += 1
            else: sandbox["other"] += 1
        tool_calls += sum(
            1 for entry in in_window
            if entry.get("type") == "response_item"
            and string_at(entry, "payload", "type") in ("function_call", "custom_tool_call", "collab_tool_call", "tool_call", "tool_use")
        )
        usage = next((
            entry.get("payload", {}).get("info", {}).get("total_token_usage")
            for entry in reversed(in_window)
            if isinstance(entry.get("payload"), dict)
            and entry["payload"].get("type") == "token_count"
            and isinstance(entry["payload"].get("info"), dict)
            and isinstance(entry["payload"]["info"].get("total_token_usage"), dict)
        ), None)
        if usage is not None:
            aliases = {"input": ("input_tokens",), "cached_input": ("cached_input_tokens", "cached_tokens"), "output": ("output_tokens",), "reasoning": ("reasoning_output_tokens", "reasoning_tokens")}
            for target, names in aliases.items():
                value = next((usage.get(name) for name in names if isinstance(usage.get(name), int) and not isinstance(usage.get(name), bool) and usage.get(name) >= 0), None)
                if value is not None:
                    tokens[target] += value
                    token_evidence = True

    session_key = next(iter(session_ids)) if len(session_ids) == 1 else path
    for entry_index, entry in enumerate(in_window):
        item = completed_spawn_item(entry)
        if item is not None and child_role is None:
            receivers = item.get("receiver_agents")
            if isinstance(receivers, list):
                for receiver in receivers:
                    role = string_at(receiver, "agent_role")
                    receiver_thread = string_at(receiver, "thread_id")
                    spawn_id = string_at(item, "id")
                    spawn_key = (session_key, spawn_id or entry_index, role, receiver_thread)
                    if spawn_key in seen_spawns:
                        continue
                    seen_spawns.add(spawn_key)
                    if role in ("advisor-terra", "advisor-sol"):
                        parent_spawns[role] += 1
                        parent_completion_evidence = True
                    elif role == "sol_advisor":
                        stale_underscore += 1
                    elif role == "sol-advisor":
                        stale_hyphen += 1
        requested_role = advisor_spawn_request(entry) if child_role is None else None
        if requested_role is not None:
            payload = entry["payload"]
            request_id = string_at(payload, "call_id") or string_at(payload, "id")
            request_key = (session_key, request_id or entry_index)
            if request_key not in seen_requests:
                seen_requests.add(request_key)
                parent_spawn_requests += 1
                parent_request_evidence = True
        activity = subagent_activity_item(entry) if child_role is None else None
        if activity is not None:
            activity_thread = string_at(activity, "agent_thread_id")
            kind = string_at(activity, "kind")
            if activity_thread in advisor_child_ids and kind in parent_activity:
                activity_id = string_at(activity, "id")
                activity_key = (session_key, activity_id or entry_index, activity_thread, kind)
                if activity_key not in seen_activity:
                    seen_activity.add(activity_key)
                    parent_activity[kind] += 1
                    parent_activity_evidence = True
        for text in receipt_texts(entry) if child_role is None else ():
            stamp = entry_time(entry)
            decision = receipt_fields(text, "ADVISOR DECISION", {"route"})
            route = decision.get("route")
            decision_key = (session_key, stamp, "decision", route)
            if route in decision_routes and decision_key not in seen_receipts:
                seen_receipts.add(decision_key)
                decision_routes[route] += 1
                decision_evidence = True
            call = receipt_fields(text, "ADVISOR CALL", {"tier", "role", "status"})
            call_key = (session_key, stamp, "call", tuple(sorted(call.items())))
            if call and call.get("status") == "running" and call_key not in seen_receipts:
                seen_receipts.add(call_key)
                attempts += 1
                if call.get("tier") == "Standard" and call.get("role") == "advisor-terra": standard += 1
                if call.get("tier") == "Specialist" and call.get("role") == "advisor-sol": specialist += 1
            result = receipt_fields(text, "ADVISOR RESULT", {"status", "decision"})
            result_key = (session_key, stamp, "result", tuple(sorted(result.items())))
            if result and result_key not in seen_receipts:
                seen_receipts.add(result_key)
                if result.get("status") == "completed": completed += 1
                elif result.get("status") == "unavailable": unavailable += 1
                if result.get("decision") == "blocked": blocked += 1
                elif result.get("decision") == "accept": accept += 1
                elif result.get("decision") == "modify": modify += 1
                elif result.get("decision") == "reject": reject += 1

duration_report = {"count": len(durations), "total_ms": sum(durations) if durations else None, "minimum_ms": min(durations) if durations else None, "maximum_ms": max(durations) if durations else None, "average_ms": round(sum(durations) / len(durations)) if durations else None, "availability": "evidenced" if durations else "unavailable"}
disposition_evidence = (completed + unavailable + blocked + accept + modify + reject) > 0
child_total = sum(child_sessions.values())
parent_spawn_total = sum(parent_spawns.values())
report = {
    "schema_version": 2,
    "redacted": True,
    "window": {"since": iso(since), "until": iso(until)},
    "decisions": decision_routes,
    "availability": {"decisions": "evidenced" if decision_evidence else "unavailable"},
    "consultations": {
        "attempted": attempts,
        "advisor_child_sessions": {"total": child_total, "by_role": child_sessions},
        "parent_spawn_completions": {
            "total": parent_spawn_total if parent_completion_evidence else None,
            "by_role": parent_spawns if parent_completion_evidence else None,
            "availability": "evidenced" if parent_completion_evidence else "unavailable",
        },
        "parent_spawn_requests": {
            "count": parent_spawn_requests if parent_request_evidence else None,
            "availability": "evidenced" if parent_request_evidence else "unavailable",
        },
        "parent_subagent_activity": {
            "count": sum(parent_activity.values()) if parent_activity_evidence else None,
            "by_kind": parent_activity if parent_activity_evidence else None,
            "availability": "evidenced" if parent_activity_evidence else "unavailable",
        },
        "selected_roles": {"standard": standard, "specialist": specialist},
        "dispositions": {"completed": completed, "unavailable": unavailable, "blocked": blocked, "accept": accept, "modify": modify, "reject": reject},
        "availability": {"dispositions": "evidenced" if disposition_evidence else "unavailable"},
    },
    "runtime": {"sandbox_counts": sandbox if sandbox_evidence else None, "advisor_tool_calls": tool_calls if tool_evidence else None, "child_durations": duration_report, "tokens": tokens if token_evidence else None, "availability": {"sandbox_counts": "evidenced" if sandbox_evidence else "unavailable", "advisor_tool_calls": "evidenced" if tool_evidence else "unavailable", "tokens": "evidenced" if token_evidence else "unavailable"}},
    "stale_role_attempts": {"sol_advisor": stale_underscore, "sol-advisor": stale_hyphen},
}
print(json.dumps(report, sort_keys=True, separators=(",", ":")))
PY
