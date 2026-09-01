---
name: consultation
description: Consult for material architecture, interface, data-model, or compatibility choices; cross-module, process, persistence, trust, or concurrency boundaries; competing diagnoses after evidence; security, privacy, authorization, migration, recovery, or irreversible-state changes; and explicit advisor, challenge, second-opinion, or architecture-review requests; and the completion consultation that complex multi-phase or multi-file work takes before it is declared complete. Skip factual/status/summarization work, fully determined mechanical edits, formatting/renaming/docs synchronization, settled-plan execution, final review owned elsewhere, explicit no-delegation/root-only requests, and every borderline case.
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

Read-only discovery may ground the decision. For a consult candidate, inspect the
parent identity before the first implementation write and before its decision record:

```sh
sh <absolute-installed-plugin-root>/scripts/inspect-parent-runtime.sh
```

The preflight uses only `CODEX_THREAD_ID` and the caller-supplied/default sessions
root. It accepts an unambiguous persisted parent with a recognized sandbox policy;
the parent itself need not be read-only because the consultation runs in a distinct
explicitly read-only Codex process. A missing, ambiguous, malformed, or conflicting
parent runtime is unavailable. Do not use `CODEX_SESSION_ID` as a fallback. Emit
exactly one record:

```text
ADVISOR DECISION
route: consult | skip | unavailable
reason: <one task-specific sentence>
question: <bounded decision question, or none>
```

Consult when at least one positive trigger in the description applies. Skip when all
applicable work is routine, the user forbids delegation, or eligibility is borderline.
General quality is not a decision question.

Complex work takes one completion consultation before it is declared complete. This
applies when the task already took `route: consult`, or when it spans multiple phases,
files, or sessions. Emit a second `ADVISOR DECISION` and consult before reporting the
work done. The bounded question is whether the finished work meets its stated contract
and what evidence would falsify that. It is not a final diff review or release
verification, which stay outside this plugin and with their existing owner: the root
still owns verification and acceptance, and the advisor still uses zero tools and sees
only the packet. Routine, single-step, and already-skipped work takes no completion
consultation.

An identified parent uses `route: consult`, including a normal `workspace-write`
root. An unavailable parent uses `route: unavailable`, emits no `ADVISOR CALL`,
starts no consultation process, and does not block the root's own work. The ordinary
`route: skip` path is unchanged.
A non-Codex surface has no supported local transport, so it takes `route: unavailable` and emits no `ADVISOR CALL` or `ADVISOR RESULT`.

## Consult exactly

1. Resolve the absolute installed plugin root from this loaded `SKILL.md` path: it is
   two directories above the directory containing this file. Verify that
   `run-advisor.sh`, `inspect-parent-runtime.sh`, and `inspect-agent-runtime.sh` are
   regular, nonsymlinked files beneath that installed root. Use those absolute paths
   for every consultation command. Never elevate a repository-relative or
   workspace-resolved `plugins/advisor` script.
2. Classify the decision risk. Standard consultation uses
   `--role advisor-terra`, pinned to `gpt-5.6-terra` / `high`. This is the
   default for material architecture, interface, data-model, compatibility,
   cross-boundary, competing-diagnosis, and explicit generic advisor requests.
   Specialist consultation uses `--role advisor-sol`, pinned to
   `gpt-5.6-sol` / `high`, only for an unresolved security or trust boundary, an
   irreversible migration or data-loss decision, or a credible unresolved High-severity disagreement.
   Security adjacency or project importance alone
   does not qualify. A borderline role choice uses `advisor-terra`. The parent
   model and sandbox are irrelevant to selection.
3. Before invoking the consultation transport, emit this visible main-chat receipt:

```text
ADVISOR CALL
tier: Standard | Specialist
role: advisor-terra | advisor-sol
reason: <one task-specific sentence>
question: <bounded decision question>
status: running
```

4. Send only this bounded, non-sensitive packet to the fixed transport on stdin:

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

5. Run exactly one selected consultation. Invoke the fixed installed-plugin wrapper
   with the shell tool's `sandbox_permissions: require_escalated` boundary and a
   narrow justification for launching one read-only Advisor child. Do not first try
   the wrapper inside the parent sandbox: nested Codex app-server initialization is
   blocked there. The elevation applies only to the fixed launcher; the consultation
   process itself is forced to `--sandbox read-only` and must pass runtime inspection.
   Do not call `codex exec` directly and do not pass a model or effort override;
   `run-advisor.sh` maps the exact role label to
   its pinned model, forces High effort and `--sandbox read-only`, starts a fresh
   `codex exec` thread using existing Codex authentication, and never reads or copies
   authentication files:

```sh
/bin/sh <absolute-installed-plugin-root>/scripts/run-advisor.sh --role advisor-terra <<'ADVISOR_PACKET'
DECISION
<the complete five-section packet continues here>
ADVISOR_PACKET
# or use: --role advisor-sol
```

   Use this single-quoted heredoc form, after proving the delimiter is absent from the
   packet. Never use `< packet.txt`, an unquoted heredoc, `eval`, or shell-interpolated
   packet text at this elevated boundary. The packet exists only on the wrapper's
   stdin; do not stage it in a workspace-writable file.

   The wrapper writes progress only to stderr and emits one verified JSON object on
   stdout. It runtime-inspects every launched child before classifying that child's
   response. Structural recognition tolerates only trailing spaces or tabs on response
   lines, using a separate validation copy so successful response bytes are preserved
   exactly. Leading indentation, a nonliteral-space separator, and missing, duplicate,
   renamed, misordered, or empty-valued fields remain
   malformed. Mandatory post-response inspection proves the exact selected model,
   High effort, read-only isolation, distinct-thread identity, `codex_exec` provenance,
   and zero tool calls before parsing can succeed. When the first child proves the exact selected model, High effort,
   read-only runtime, distinct thread, allowlisted `codex_exec` or `Codex Desktop`
   provenance, and zero tool calls but
   returns an empty or malformed response, the wrapper emits retry progress on stderr
   and performs exactly one fresh retry by launching a new child. Packet, launcher, event, identity,
   same-session, runtime, wrong-model, wrong-effort, non-read-only, normalization, or tool-use failure
   is terminal and never retries. A second empty or malformed response fails closed;
   the rejected first response is never accepted or merged.
6. Receive the required advisor response from the verified JSON without supplying
   more context or asking it to research. A valid processed response contains either
   a recommendation grounded in the packet or a concrete research-first follow-up
   under `FOLLOW-UP AREAS`.
7. Treat a response that passed mandatory runtime inspection as evidence and verify
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

8. After a valid, runtime-inspected completed result, the root may route only the
   identified research or brainstorming follow-up to an appropriate Luna or Terra
   subagent outside this consultation, synthesize that work, and optionally start a
   fresh consultation with a new `ADVISOR CALL` and `ADVISOR RESULT` receipt. Those
   subagents do not rescue or alter the original consultation result. An unavailable result cannot be rescued by follow-up work.
9. The advisor may not spawn, route, research, implement, or review final work. Do
   not independently spawn a replacement or second advisor, implementer, or final
   reviewer as part of this consultation. The wrapper-owned response retry above is
   the only permitted second child.

`completed` requires a processed advisor response with either a recommendation or a
concrete `FOLLOW-UP AREAS` entry, plus mandatory post-response runtime inspection.
Any unavailable runtime evidence, non-read-only runtime policy, tool-use evidence, or
required advice produces `status: unavailable`,
`recommendation: unavailable`, and `decision: blocked` and remains fail-closed.
These receipts summarize verified evidence; they are not runtime proof.
The distinct Codex consultation thread remains the inspectable detailed record.

If exact completed transport evidence is unavailable, report `advisor unavailable`
and block the consult route. Never continue independently, substitute another role,
or add an implementer or final reviewer after choosing `consult`.
In all cases, never substitute a role other than the policy-selected
`advisor-terra` or `advisor-sol`.

For `skip` or `unavailable`, emit only the existing `ADVISOR DECISION`; do not emit
`ADVISOR CALL` or `ADVISOR RESULT`, and do not start the transport. An unavailable parent does not
block root-owned work.

See [operations](references/operations.md) for installation, runtime evidence, and
evaluation details.
