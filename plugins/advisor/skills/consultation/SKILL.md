---
name: consultation
description: Consult for material architecture, interface, data-model, or compatibility choices; cross-module, process, persistence, trust, or concurrency boundaries; competing diagnoses after evidence; security, privacy, authorization, migration, recovery, or irreversible-state changes; and explicit advisor, challenge, second-opinion, or architecture-review requests. Skip factual/status/summarization work, fully determined mechanical edits, formatting/renaming/docs synchronization, settled-plan execution, final review owned elsewhere, explicit no-delegation/root-only requests, and every borderline case.
---

# Advisor consultation

Use one fresh, read-only, zero-tool advisor only when the task has a concrete material
decision. The root remains architect, implementer-or-router, verifier, and acceptor.
Before consultation, the root performs any repository or web research and includes
only the relevant evidence and source references in the five-section decision packet.
The advisor does not inspect files, call tools, fetch the web, or conduct independent
research.

## Declare the route

Read-only discovery may ground the decision. Before the first implementation write,
emit exactly one record:

```text
ADVISOR DECISION
route: consult | skip
reason: <one task-specific sentence>
question: <bounded decision question, or none>
```

Consult when at least one positive trigger in the description applies. Skip when all
applicable work is routine, the user forbids delegation, or eligibility is borderline.
General quality is not a decision question.

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
Challenge the tentative choice. Recommend one path, identify the strongest
counterargument, name evidence that would change the recommendation, and give
specific acceptance checks. Use zero tools: do not inspect files, call tools, fetch
the web, or conduct independent research. If the packet is insufficient, name the
specific missing evidence under CHANGE MY MIND instead of researching.
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
```

7. Receive the required advisor response without supplying more context or asking it
   to research.
8. Immediately after every native advisor response, run
   `inspect-agent-runtime.sh` for the selected thread and expected role/model. This
   inspection is mandatory, not a metadata fallback, and must complete before any
   `ADVISOR RESULT` with `status: completed`. It verifies the runtime policy remains
   read-only and that the advisor made no tool call. Any missing, conflicting,
   non-read-only, or tool-use evidence makes the advisor unavailable and blocks the
   consult route.
9. Treat a response that passed mandatory runtime inspection as evidence, verify its
   cited source references, then record `accept`, `modify`, or `reject` with one
   reason. After runtime evidence and advice processing, always emit this visible
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

`completed` requires a processed advisor response and mandatory post-response runtime
inspection. Any unavailable runtime evidence, non-read-only runtime policy, tool-use
evidence, or required advice produces `status: unavailable`,
`recommendation: unavailable`, and `decision: blocked` and remains fail-closed.
These receipts summarize verified evidence; they are not runtime proof.
The native child thread remains the inspectable detailed record.

If the exact completed spawn evidence is unavailable, report `advisor unavailable`
and block the consult route. Never continue independently, substitute another role,
or add an implementer or final reviewer after choosing `consult`.
In all cases, never substitute a role other than the policy-selected
`advisor-terra` or `advisor-sol`.

For `skip`, emit only the existing `ADVISOR DECISION`; do not emit `ADVISOR CALL` or
`ADVISOR RESULT`, and do not spawn.

See [operations](references/operations.md) for installation, runtime evidence, and
evaluation details.
