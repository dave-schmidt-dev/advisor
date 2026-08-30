---
name: consultation
description: Consult for material architecture, interface, data-model, or compatibility choices; cross-module, process, persistence, trust, or concurrency boundaries; competing diagnoses after evidence; security, privacy, authorization, migration, recovery, or irreversible-state changes; and explicit advisor, challenge, second-opinion, or architecture-review requests. Skip factual/status/summarization work, fully determined mechanical edits, formatting/renaming/docs synchronization, settled-plan execution, final review owned elsewhere, explicit no-delegation/root-only requests, and every borderline case.
---

# Advisor consultation

Use one fresh, read-only, zero-tool advisor only when the task has a concrete material
decision. The root remains architect, implementer-or-router, verifier, and acceptor.
Before consultation, the root performs any repository or web research and supplies
enough relevant evidence and source references in the five-section decision packet for
the advisor to recommend a path. If that evidence cannot settle the question, a valid
advisor result may instead identify a concrete research-first next step, missing
evidence, research questions, or bounded brainstorming areas. The advisor does not
inspect files, call tools, fetch the web, or conduct independent research.

## Declare the route

Read-only discovery may ground the decision. For a consult candidate, run the parent
runtime preflight before the first implementation write and before its decision record:

```sh
sh plugins/advisor/scripts/inspect-parent-runtime.sh
```

The preflight uses only `CODEX_THREAD_ID` and the caller-supplied/default sessions
root. It must return `status: available` with `sandbox_policy_type: read-only`; a
missing, ambiguous, malformed, conflicting, or non-read-only parent runtime is
unavailable. Do not use `CODEX_SESSION_ID` as a fallback. Emit exactly one record:

```text
ADVISOR DECISION
route: consult | skip | unavailable
reason: <one task-specific sentence>
question: <bounded decision question, or none>
```

Consult when at least one positive trigger in the description applies. Skip when all
applicable work is routine, the user forbids delegation, or eligibility is borderline.
General quality is not a decision question.

A proven read-only parent uses `route: consult`. An unavailable parent, including
`workspace-write`, uses `route: unavailable`, emits no `ADVISOR CALL`, spawns no
child, and does not block the root's own work. The ordinary `route: skip` path is
unchanged.

## Consult exactly

1. Run the companion installer in check mode and verify that installed
   `advisor-terra` and `advisor-sol` TOMLs byte-match both shipped roles.
2. Classify the decision risk. Standard consultation uses
   `agent_type: advisor-terra`, pinned to `gpt-5.6-terra` / `high`. This is the
   default for material architecture, interface, data-model, compatibility,
   cross-boundary, competing-diagnosis, and explicit generic advisor requests.
   Specialist consultation uses `agent_type: advisor-sol`, pinned to
   `gpt-5.6-sol` / `high`, only for an unresolved security or trust boundary, an
   irreversible migration or data-loss decision, or a credible unresolved High-severity disagreement.
   Security adjacency or project importance alone
   does not qualify. A borderline role choice uses `advisor-terra`. The parent
   model is irrelevant, so Terra may advise Luna.
3. Before spawning, emit this visible main-chat receipt:

```text
ADVISOR CALL
tier: Standard | Specialist
role: advisor-terra | advisor-sol
reason: <one task-specific sentence>
question: <bounded decision question>
status: running
```

4. Spawn exactly one selected role. Do not pass a model or effort override because
   live Codex may ignore it; the installed role is the enforcement boundary. With
   host schema v2 use `fork_turns: none`; with v1 use `fork_context: false`.
   Never send both or inherit context.
5. Verify the completed `spawn_agent` event first: the exact selected role/model
   pair, `high` effort, one receiver thread distinct from the root, and read-only
   isolation requested by invocation and role files. Conflicts or missing evidence
   block the consult route.
6. Send only this bounded, non-sensitive packet:

```text
DECISION
<one question the root must resolve>

CONTEXT
<goal, relevant root-gathered evidence with source references, and current constraints>

OPTIONS
<known viable choices, including the tentative choice when one exists>

BOUNDARIES
<owned files, excluded scope, compatibility, security, and authority limits>

REQUEST
Challenge the tentative choice. Recommend one path when the packet supports a
decision; otherwise identify a concrete research-first next step, specific missing evidence,
research questions, or bounded brainstorming areas. Identify the strongest
counterargument, name evidence that would change the recommendation, and give
specific acceptance checks. Use zero tools: do not inspect files, call tools, fetch
the web, or conduct independent research. Do not perform or delegate the follow-up.
```

Require exactly:

```text
ADVISOR RESPONSE
RECOMMENDATION: <one path>
WHY: <decisive evidence and reasoning>
STRONGEST OBJECTION: <best case against the recommendation>
CHANGE MY MIND: <specific missing or contrary evidence>
ACCEPTANCE CHECKS: <concrete checks>
RISKS: <material residual risks, or none>
FOLLOW-UP AREAS: <none, or a concrete research-first next step, missing evidence,
research questions, or bounded brainstorming areas>
```

7. Receive the required advisor response without supplying more context or asking it
   to research. A valid processed response contains either a recommendation grounded
   in the packet or a concrete research-first follow-up under `FOLLOW-UP AREAS`.
8. Immediately after every native advisor response, run
   `inspect-agent-runtime.sh` for the selected thread and expected role/model. This
   inspection is mandatory, not a metadata fallback, and must complete before any
   `ADVISOR RESULT` with `status: completed`. It verifies the runtime policy remains
   read-only and that the advisor made no tool call. Any missing, conflicting,
   non-read-only, or tool-use evidence makes the advisor unavailable and blocks the
   consult route.
9. Treat a response that passed mandatory runtime inspection as evidence and verify
   its cited source references. For a research-first response, treat the concise
   research-first plan as the recommendation and its concrete inquiries as
   `FOLLOW-UP AREAS`. Then record `accept`, `modify`, or `reject` with one reason:
   `accept` means the root accepts the returned technical recommendation or
   research-first plan, never a technical choice that the advisor did not make.
   After runtime evidence and advice processing, always emit this visible
   main-chat receipt:

```text
ADVISOR RESULT
status: completed | unavailable
tier: Standard | Specialist
role: advisor-terra | advisor-sol
model: <verified gpt-5.6-terra | gpt-5.6-sol>
effort: high
isolation: read-only
recommendation: <concise recommendation, or unavailable>
decision: accept | modify | reject | blocked
reason: <one sentence>
```

10. After a valid, runtime-inspected completed result, the root may route only the
   identified research or brainstorming follow-up to an appropriate Luna or Terra
   subagent outside this consultation, synthesize that work, and optionally start a
   fresh consultation with a new `ADVISOR CALL` and `ADVISOR RESULT` receipt. Those
   subagents do not rescue or alter the original consultation result. An unavailable result cannot be rescued by follow-up work.
11. The advisor may not spawn, route, research, implement, or review final work. Do
   not spawn a replacement, second advisor, implementer, or final reviewer as part of
   this consultation.

`completed` requires a processed advisor response with either a recommendation or a
concrete `FOLLOW-UP AREAS` entry, plus mandatory post-response runtime inspection.
Any unavailable runtime evidence, non-read-only runtime policy, tool-use evidence, or
required advice produces `status: unavailable`,
`recommendation: unavailable`, and `decision: blocked` and remains fail-closed.
These receipts summarize verified evidence; they are not runtime proof.
The native child thread remains the inspectable detailed record.

If the exact completed spawn evidence is unavailable, report `advisor unavailable`
and block the consult route. Never continue independently, substitute another role,
or add an implementer or final reviewer after choosing `consult`.
In all cases, never substitute a role other than the policy-selected
`advisor-terra` or `advisor-sol`.

For `skip` or `unavailable`, emit only the existing `ADVISOR DECISION`; do not emit
`ADVISOR CALL` or `ADVISOR RESULT`, and do not spawn. An unavailable parent does not
block root-owned work.

See [operations](references/operations.md) for installation, runtime evidence, and
evaluation details.
