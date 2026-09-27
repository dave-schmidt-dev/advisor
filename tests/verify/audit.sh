# shellcheck shell=sh
# Sourced by plugins/advisor/scripts/verify.sh; do not run directly.
audit_sessions=$tmp/audit-sessions; mkdir -p "$audit_sessions/2026/01/01"
python3 - "$audit_sessions/2026/01/01" <<'PY'
import json,sys
from pathlib import Path

root=Path(sys.argv[1])
def write(name, entries):
    root.joinpath(name).write_text("".join(json.dumps(entry)+"\n" for entry in entries),encoding="utf-8")
def stamp(second):
    return f"2026-01-01T00:00:{second:02d}Z"
def receipt(heading, **fields):
    return heading+"\n"+"\n".join(f"{key}: {value}" for key,value in fields.items())+"\nDO_NOT_LEAK_SECRET_PROMPT api_key=sk-forbidden contact@example.test"
def message(text, second):
    return {"timestamp":stamp(second),"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":text}]}}
def spawn(role, second):
    return {"timestamp":stamp(second),"type":"event_msg","payload":{"type":"item_completed","item":{"id":f"spawn-{role}-{second}","type":"CollabAgentToolCall","tool":"spawn_agent","status":"completed","receiver_agents":[{"agent_role":role,"thread_id":f"receiver-{role}-{second}"}]}}}
def legacy_spawn(role, second):
    return {"timestamp":stamp(second),"type":"response_item","payload":{"id":f"legacy-{role}-{second}","type":"collab_tool_call","tool":"spawn_agent","status":"completed","receiver_agents":[{"agent_role":role,"thread_id":f"legacy-receiver-{role}-{second}"}]}}
def request(role, second, call_id):
    arguments=json.dumps({"agent_type":role,"fork_turns":"none","message":"DO_NOT_LEAK_REQUEST_PROMPT api_key=sk-request-secret","task_name":"private-task"})
    return {"timestamp":stamp(second),"type":"response_item","payload":{"type":"function_call","name":"spawn_agent","namespace":"functions","call_id":call_id,"arguments":arguments}}
def activity(thread_id, kind, second, item_id):
    return {"timestamp":stamp(second),"type":"event_msg","payload":{"type":"item_completed","item":{"type":"SubAgentActivity","id":item_id,"agent_thread_id":thread_id,"agent_path":"DO_NOT_LEAK_AGENT_PATH","kind":kind}}}
root_meta={"timestamp":"2025-12-31T23:59:00Z","type":"session_meta","payload":{"id":"root-private-id","agent_role":"root","source":{"private":"DO_NOT_LEAK_SOURCE"}}}
duplicate_call=message(receipt("ADVISOR CALL",tier="Standard",role="advisor-terra",status="running"),2)
write("root.jsonl",[
    root_meta,
    message(receipt("ADVISOR DECISION",route="consult"),1),
    duplicate_call, duplicate_call,
    spawn("advisor-terra",3), spawn("advisor-terra",3),
    message(receipt("ADVISOR RESULT",status="completed",decision="accept"),4),
    message(receipt("ADVISOR DECISION",route="skip"),5),
    message(receipt("ADVISOR DECISION",route="unavailable"),6),
    message(receipt("ADVISOR DECISION",route="forbidden"),7),
    message("ADVISOR DECISION\nroute: consult\nroute: skip\nDO_NOT_LEAK_DUPLICATE_ROUTE",7),
    message(receipt("ADVISOR CALL",tier="Specialist",role="advisor-sol",status="running"),8),
    legacy_spawn("advisor-sol",9),
    message(receipt("ADVISOR RESULT",status="unavailable",decision="blocked"),10),
    spawn("sol_advisor",11), spawn("sol-advisor",12),
    request("advisor-terra",13,"request-terra"), request("advisor-terra",13,"request-terra"),
    request("advisor-sol",14,"request-sol"),
    activity("terra-private-id","started",15,"activity-terra-started"),
    activity("terra-private-id","interacted",15,"activity-terra-interacted"),
    activity("terra-private-id","completed",16,"activity-terra-completed"),
    activity("sol-private-id","started",17,"activity-sol-started"),
    activity("sol-private-id","interrupted",17,"activity-sol-interrupted"),
    activity("sol-private-id","completed",18,"activity-sol-completed"),
    activity("sol-private-id","completed",18,"activity-sol-completed"),
    spawn("advisor-astra",19),
])
terra_entries=[
    {"timestamp":"2025-12-31T23:59:59Z","type":"session_meta","payload":{"agent_role":"advisor-terra","id":"terra-private-id","source":{"subagent":{"thread_spawn":{"agent_role":"advisor-terra"}}},"prompt":"DO_NOT_LEAK_TERRA_META"}},
    {"timestamp":stamp(11),"type":"turn_context","payload":{"sandbox_policy":{"type":"read-only"}}},
    message(receipt("ADVISOR DECISION",route="unavailable"),12),
    {"timestamp":stamp(12),"type":"response_item","payload":{"type":"custom_tool_call","text":"DO_NOT_LEAK_TOOL"}},
    {"timestamp":stamp(13),"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3,"reasoning_output_tokens":4}}}},
]
write("terra.jsonl",terra_entries)
write("terra-duplicate-session.jsonl",terra_entries)
write("sol.jsonl",[
    {"timestamp":stamp(20),"type":"session_meta","payload":{"agent_role":"advisor-sol","id":"sol-private-id","source":{"subagent":{"thread_spawn":{"agent_role":"advisor-sol"}}}}},
    {"timestamp":stamp(22),"type":"turn_context","payload":{"sandbox_policy":{"type":"workspace-write"}}},
    {"timestamp":stamp(23),"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"DO_NOT_LEAK_RESPONSE"}]}},
    {"timestamp":stamp(24),"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20,"cached_input_tokens":5,"output_tokens":6,"reasoning_output_tokens":7}}}},
])
write("astra.jsonl",[
    {"timestamp":stamp(25),"type":"session_meta","payload":{"agent_role":"advisor-astra","id":"astra-private-id","source":{"subagent":{"thread_spawn":{"agent_role":"advisor-astra"}}}}},
])
# A legacy nested role mention is parent metadata, not exact current child metadata.
write("legacy-nested-role.jsonl",[
    {"timestamp":stamp(30),"type":"session_meta","payload":{"id":"legacy-private-id","source":{"subagent":{"thread_spawn":{"agent_role":"advisor-sol"}}}}},
    {"timestamp":stamp(31),"type":"turn_context","payload":{"sandbox_policy":{"type":"read-only"}}},
])
# Exact child metadata with no activity in the selected window must not count.
write("outside-window.jsonl",[
    {"timestamp":"2026-01-02T00:00:00Z","type":"session_meta","payload":{"agent_role":"advisor-terra","id":"outside-private-id"}},
    {"timestamp":"2026-01-02T00:00:01Z","type":"turn_context","payload":{"sandbox_policy":{"type":"read-only"}}},
])
PY
audit_out=$tmp/advisor-audit.json
audit_err=$tmp/advisor-audit.stderr
audit_before=$(snapshot "$audit_sessions/2026/01/01")
sh "$audit" --sessions-dir "$audit_sessions" --since 2026-01-01T00:00:00Z --until 2026-01-02T00:00:00Z >"$audit_out" 2>"$audit_err"
audit_after=$(snapshot "$audit_sessions/2026/01/01")
[ "$audit_before" = "$audit_after" ] || fail "advisor audit modified session fixtures"
jq -e '
  .schema_version==2 and .redacted==true and
  .decisions=={"consult":1,"skip":1,"unavailable":1} and
  .availability.decisions=="evidenced" and
  .consultations.attempted==2 and
  .consultations.advisor_child_sessions=={"total":3,"by_role":{"advisor-astra":1,"advisor-terra":1,"advisor-sol":1}} and
  .consultations.parent_spawn_completions=={"total":3,"by_role":{"advisor-astra":1,"advisor-terra":1,"advisor-sol":1},"availability":"evidenced"} and
  .consultations.parent_spawn_requests=={"count":2,"availability":"evidenced"} and
  .consultations.parent_subagent_activity=={"count":6,"by_kind":{"started":2,"interacted":1,"completed":2,"interrupted":1},"availability":"evidenced"} and
  .consultations.selected_roles=={"standard":1,"specialist":1} and
  .consultations.dispositions=={"completed":1,"unavailable":1,"blocked":1,"accept":1,"modify":0,"reject":0} and
  .runtime.sandbox_counts=={"read_only":1,"workspace_write":1,"other":0} and
  .runtime.advisor_tool_calls==1 and
  .runtime.child_durations=={"count":2,"total_ms":6000,"minimum_ms":2000,"maximum_ms":4000,"average_ms":3000,"availability":"evidenced"} and
  .runtime.tokens=={"input":30,"cached_input":7,"output":9,"reasoning":11} and
  .runtime.availability=={"sandbox_counts":"evidenced","advisor_tool_calls":"evidenced","tokens":"evidenced"} and
  .stale_role_attempts=={"sol_advisor":1,"sol-advisor":1}
' "$audit_out" >/dev/null || fail "advisor audit aggregate report mismatch"
grep -Fq 'ADVISOR AUDIT: session enumeration started' "$audit_err" || fail "advisor audit lacks enumeration progress"
grep -Fq 'ADVISOR AUDIT: session parsing started' "$audit_err" || fail "advisor audit lacks parsing progress"
if grep -Eqi 'DO_NOT_LEAK|private-id|receiver-|request-|activity-|root\.jsonl|secret_prompt|api_key|contact@example|sk-forbidden|private-task' "$audit_out" "$audit_err"; then fail "advisor audit leaked fixture content or identifiers"; fi
empty_sessions=$tmp/empty-audit-sessions; mkdir "$empty_sessions"
empty_audit=$tmp/empty-advisor-audit.json
sh "$audit" --sessions-dir "$empty_sessions" --since 2026-01-01T00:00:00Z --until 2026-01-02T00:00:00Z >"$empty_audit" 2>/dev/null
jq -e '
  .decisions=={"consult":0,"skip":0,"unavailable":0} and .availability.decisions=="unavailable" and
  .consultations.advisor_child_sessions=={"total":0,"by_role":{"advisor-astra":0,"advisor-terra":0,"advisor-sol":0}} and
  .consultations.parent_spawn_completions=={"total":null,"by_role":null,"availability":"unavailable"} and
  .consultations.parent_spawn_requests=={"count":null,"availability":"unavailable"} and
  .consultations.parent_subagent_activity=={"count":null,"by_kind":null,"availability":"unavailable"} and
  .runtime.sandbox_counts==null and .runtime.advisor_tool_calls==null and
  .runtime.tokens==null and .runtime.child_durations.availability=="unavailable" and
  .runtime.availability=={"sandbox_counts":"unavailable","advisor_tool_calls":"unavailable","tokens":"unavailable"}
' "$empty_audit" >/dev/null || fail "advisor audit guessed unavailable evidence"

corroboration_sessions=$tmp/corroboration-audit-sessions; mkdir -p "$corroboration_sessions/2026/01/01"
python3 - "$corroboration_sessions/2026/01/01" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1])
def write(name,entries): root.joinpath(name).write_text("".join(json.dumps(entry)+"\n" for entry in entries),encoding="utf-8")
def entry(second,type_,payload): return {"timestamp":f"2026-01-01T00:00:{second:02d}Z","type":type_,"payload":payload}
child_id="corroborated-child-private-id"
write("child.jsonl",[
  entry(1,"session_meta",{"id":child_id,"agent_role":"advisor-terra"}),
  entry(2,"turn_context",{"sandbox_policy":{"type":"read-only"}}),
])
arguments=json.dumps({"agent_type":"advisor-sol","fork_turns":"none","message":"DO_NOT_LEAK_REQUEST_ONLY","task_name":"private-request"})
write("parent.jsonl",[
  entry(1,"session_meta",{"id":"corroboration-parent-private-id","agent_role":"root"}),
  entry(2,"response_item",{"type":"function_call","name":"spawn_agent","call_id":"request-only-private-id","arguments":arguments}),
  entry(3,"event_msg",{"type":"item_completed","item":{"type":"SubAgentActivity","id":"started-private-id","agent_thread_id":child_id,"agent_path":"DO_NOT_LEAK_PATH","kind":"started"}}),
  entry(4,"event_msg",{"type":"item_completed","item":{"type":"SubAgentActivity","id":"completed-private-id","agent_thread_id":child_id,"agent_path":"DO_NOT_LEAK_PATH","kind":"completed"}}),
])
PY
corroboration_audit=$tmp/corroboration-audit.json
sh "$audit" --sessions-dir "$corroboration_sessions" --since 2026-01-01T00:00:00Z --until 2026-01-02T00:00:00Z >"$corroboration_audit" 2>/dev/null
jq -e '
  .consultations.advisor_child_sessions.total==1 and
  .consultations.parent_spawn_completions=={"total":null,"by_role":null,"availability":"unavailable"} and
  .consultations.parent_spawn_requests=={"count":1,"availability":"evidenced"} and
  .consultations.parent_subagent_activity=={"count":2,"by_kind":{"started":1,"interacted":0,"completed":1,"interrupted":0},"availability":"evidenced"}
' "$corroboration_audit" >/dev/null || fail "advisor audit inferred completion or role counts from current parent corroboration"
if grep -Eqi 'DO_NOT_LEAK|private-id|private-request' "$corroboration_audit"; then fail "advisor audit leaked corroboration fixture content"; fi
pass "advisor audit schema v2 current/legacy fixtures, exact decisions, current parent corroboration, fail-closed completion availability, window ordering, deduplication, redaction, unavailable evidence, and stderr progress"
