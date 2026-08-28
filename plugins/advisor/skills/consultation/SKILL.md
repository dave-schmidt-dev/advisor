---
name: consultation
description: Consult for material architecture, interface, data-model, or compatibility choices; cross-module, process, persistence, trust, or concurrency boundaries; competing diagnoses after evidence; security, privacy, authorization, migration, recovery, or irreversible-state changes; and explicit advisor, challenge, second-opinion, or architecture-review requests. Skip factual/status/summarization work, fully determined mechanical edits, formatting/renaming/docs synchronization, settled-plan execution, final review owned elsewhere, explicit no-delegation/root-only requests, and every borderline case.
---

# Advisor consultation

Use one fresh, read-only advisor only when the task has a concrete material decision.
The root remains architect, implementer-or-router, verifier, and acceptor.

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
3. Spawn exactly one selected role. Do not pass a model or effort override because
   live Codex may ignore it; the installed role is the enforcement boundary. With
   host schema v2 use `fork_turns: none`; with v1 use `fork_context: false`.
   Never send both or inherit context.
4. Verify the completed `spawn_agent` event first: the exact selected role/model
   pair, `high` effort, one receiver thread distinct from the root, and read-only
   isolation established by invocation and role files. The local inspector may fill
   only fields omitted by public metadata. Conflicts or missing evidence block the
   consult route.
5. Send only this bounded, non-sensitive packet:

```text
DECISION
<one question the root must resolve>

CONTEXT
<goal, observed evidence, and current constraints>

OPTIONS
<known viable choices, including the tentative choice when one exists>

BOUNDARIES
<owned files, excluded scope, compatibility, security, and authority limits>

REQUEST
Challenge the tentative choice. Recommend one path, identify the strongest
counterargument, name evidence that would change the recommendation, and give
specific acceptance checks. Remain read-only.
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

Treat the response as evidence, verify cited repository facts, then record `accept`,
`modify`, or `reject` with one reason.

If the exact completed spawn evidence is unavailable, report `advisor unavailable`
and block the consult route. Never continue independently, substitute another role,
or add an implementer or final reviewer after choosing `consult`.
In all cases, never substitute a role other than the policy-selected
`advisor-terra` or `advisor-sol`.

See [operations](references/operations.md) for installation, runtime evidence, and
evaluation details.
