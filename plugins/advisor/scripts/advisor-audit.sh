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

def receipt_fields(text, heading):
    if not isinstance(text, str) or heading not in {line.strip() for line in text.splitlines()}:
        return {}
    # Retain only fixed receipt enums; receipt prose is never retained or emitted.
    fields = {}
    for line in text.splitlines():
        match = re.fullmatch(r"\s*(tier|role|status|decision)\s*:\s*(\S+)\s*", line)
        if match:
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

def nested_objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from nested_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from nested_objects(child)

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

attempts = actual_calls = standard = specialist = 0
stale_underscore = stale_hyphen = 0
completed = unavailable = blocked = accept = modify = reject = 0
sandbox = {"read_only": 0, "workspace_write": 0, "other": 0}
sandbox_evidence = False
tool_calls = 0
tool_evidence = False
durations = []
tokens = {"input": 0, "cached_input": 0, "output": 0, "reasoning": 0}
token_evidence = False

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
    in_window = [entry for entry in entries if (stamp := entry_time(entry)) is not None and since <= stamp < until]
    if not in_window:
        continue

    child_role = next((string_at(entry, "payload", "agent_role") for entry in in_window if string_at(entry, "payload", "agent_role") in ("advisor-terra", "advisor-sol")), None)
    if child_role is not None:
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

    for entry in in_window:
        item = entry.get("payload", {}).get("item") if isinstance(entry.get("payload"), dict) else {}
        item = item if isinstance(item, dict) else {}
        if entry.get("type") == "event_msg" and string_at(entry, "payload", "type") == "item_completed" and string_at(item, "type") == "CollabAgentToolCall" and string_at(item, "tool") == "spawn_agent" and string_at(item, "status") == "completed":
            receivers = item.get("receiver_agents")
            if isinstance(receivers, list):
                for receiver in receivers:
                    role = string_at(receiver, "agent_role")
                    if role in ("advisor-terra", "advisor-sol"):
                        actual_calls += 1
                    elif role == "sol_advisor":
                        stale_underscore += 1
                    elif role == "sol-advisor":
                        stale_hyphen += 1
        for text in receipt_texts(entry):
            call = receipt_fields(text, "ADVISOR CALL")
            if call and call.get("status") == "running":
                attempts += 1
                if call.get("tier") == "Standard" and call.get("role") == "advisor-terra": standard += 1
                if call.get("tier") == "Specialist" and call.get("role") == "advisor-sol": specialist += 1
            result = receipt_fields(text, "ADVISOR RESULT")
            if result:
                if result.get("status") == "completed": completed += 1
                elif result.get("status") == "unavailable": unavailable += 1
                if result.get("decision") == "blocked": blocked += 1
                elif result.get("decision") == "accept": accept += 1
                elif result.get("decision") == "modify": modify += 1
                elif result.get("decision") == "reject": reject += 1

duration_report = {"count": len(durations), "total_ms": sum(durations) if durations else None, "minimum_ms": min(durations) if durations else None, "maximum_ms": max(durations) if durations else None, "average_ms": round(sum(durations) / len(durations)) if durations else None, "availability": "evidenced" if durations else "unavailable"}
disposition_evidence = (completed + unavailable + blocked + accept + modify + reject) > 0
report = {
    "schema_version": 1,
    "redacted": True,
    "window": {"since": iso(since), "until": iso(until)},
    "consultations": {"attempted": attempts, "advisor_child_calls": actual_calls, "selected_roles": {"standard": standard, "specialist": specialist}, "dispositions": {"completed": completed, "unavailable": unavailable, "blocked": blocked, "accept": accept, "modify": modify, "reject": reject}, "availability": {"dispositions": "evidenced" if disposition_evidence else "unavailable"}},
    "runtime": {"sandbox_counts": sandbox if sandbox_evidence else None, "advisor_tool_calls": tool_calls if tool_evidence else None, "child_durations": duration_report, "tokens": tokens if token_evidence else None, "availability": {"sandbox_counts": "evidenced" if sandbox_evidence else "unavailable", "advisor_tool_calls": "evidenced" if tool_evidence else "unavailable", "tokens": "evidenced" if token_evidence else "unavailable"}},
    "stale_role_attempts": {"sol_advisor": stale_underscore, "sol-advisor": stale_hyphen},
}
print(json.dumps(report, sort_keys=True, separators=(",", ":")))
PY
