# Advisor

Advisor adds one automatic, read-only consultation before a
material technical decision. It does not implement, route implementation, or perform
final review. The root agent owns every decision and records whether advice was
accepted, modified, or rejected.

Supported local Codex hosts: **Codex CLI and Codex desktop**. Generic ChatGPT is not
a supported runtime.

It consults for architecture, interface, data-model, compatibility, cross-boundary,
competing-diagnosis, security, privacy, authorization, migration, recovery, and
irreversible-state choices. It skips factual/status/summarization work, determined
mechanical edits, formatting/renaming/docs synchronization, settled-plan execution,
final review owned elsewhere, explicit no-delegation requests, and borderline cases.

## Install

Add the public marketplace, install the plugin, then run the companion installer
resolved from the installed plugin directory:

```sh
codex plugin marketplace add dave-schmidt-dev/advisor --ref main
codex plugin add advisor@advisor
plugin_dir="$(codex plugin list --json | jq -r '.installed[] | select(.pluginId == "advisor@advisor") | .source.path')" && test -n "$plugin_dir" && test "$plugin_dir" != null && test -d "$plugin_dir" && test -f "$plugin_dir/scripts/install-agents.sh" && sh "$plugin_dir/scripts/install-agents.sh"
```

For local development, replace the first command with:

```sh
codex plugin marketplace add /absolute/path/to/advisor
```

Start a new Codex thread after installation so the skill and custom role are
discovered. Implicit matching handles eligible decisions; an explicit request can use:

```text
Use $advisor:consultation for a fresh, read-only second opinion on this decision.
```

For a consult candidate, before `ADVISOR DECISION`, the root runs
`inspect-parent-runtime.sh`. It identifies the parent only with `CODEX_THREAD_ID` and
requires one regular, nonsymlinked persisted rollout with unambiguous recognized
sandbox and permission metadata; it never falls back to `CODEX_SESSION_ID`. A normal
`workspace-write` root is eligible because consultation isolation belongs to a
distinct process. Missing, conflicting, malformed, or duplicate evidence emits one
`ADVISOR DECISION` with `route: unavailable`, no `ADVISOR CALL`, and no consultation
process, without blocking root-owned work. Ordinary work still emits `route: skip`.
An identified parent emits `route: consult`, with a task-specific reason and bounded
question. A valid consult uses exactly one role label selected by decision risk. Standard consultation,
including generic advisor requests, uses `advisor-terra` (`gpt-5.6-terra` / High).
Specialist consultation uses `advisor-sol` (`gpt-5.6-sol` / High) only for an
unresolved security or trust boundary, an irreversible migration or data-loss
decision, or a credible unresolved High-severity disagreement. Security adjacency
and project importance alone do not qualify; a borderline role choice uses Terra.
The parent model and sandbox are irrelevant to selection. The root sends the bounded
packet on stdin to `run-advisor.sh`; the wrapper maps the role label to the exact
pinned model, forces High effort and `--sandbox read-only`, starts a distinct
persisted `codex exec` thread, and uses existing Codex authentication without reading
or copying authentication files. Because nested Codex app-server initialization is
blocked inside the parent sandbox, the root invokes only this fixed installed-plugin
wrapper through the shell tool's `require_escalated` boundary; the child remains
read-only and must pass runtime inspection. The elevated path is the absolute plugin
cache root derived from the loaded skill, never a repository-relative or
workspace-resolved script. Packet text crosses that elevated boundary only through
a single-quoted, non-interpolating heredoc on stdin and is never staged in a
workspace-writable file. Transport files live under the nonsandbox-writable Codex
home, not `$TMPDIR`. The root performs any repository or web research before
consultation and supplies enough relevant evidence and source references in the
five-section packet for a decision. Advisors use zero tools: they do not inspect
files, fetch the web, or conduct independent research. A valid inspected response
either recommends a path or identifies a concrete research-first next step, missing
evidence, research questions, or bounded brainstorming areas under `FOLLOW-UP AREAS`.
If runtime evidence is missing or conflicts, the consult route blocks.

Every consult is visible in main chat. Immediately before transport invocation, `ADVISOR CALL`
records the selected tier and role, task-specific reason, bounded question, and
`status: running`. Before classifying every response or returning any successful
machine-readable result, the wrapper runs the runtime inspector for that fresh child
and the parent thread. It must prove allowlisted `codex_exec` or `Codex Desktop` provenance, selected model,
High effort, a distinct read-only, zero-tool runtime. Response labels tolerate only
trailing spaces or tabs for structural recognition; leading indentation and a
nonliteral-space separator remain invalid. Missing, duplicate, renamed, misordered, or empty-valued fields remain malformed.
Successful output preserves the original response bytes. Only a runtime-valid first child with an empty
or structurally malformed or misordered response receives exactly one fresh retry,
with progress on stderr. Packet, launcher, event, identity, same-session, runtime,
wrong-model, wrong-effort, non-read-only, normalization, and tool-use failures are terminal and never
retry. A second empty or malformed response records `recommendation: unavailable`
and `decision: blocked` and remains fail-closed. Only then may `ADVISOR RESULT`
record `completed`, the verified model and High effort, read-only isolation, a concise
recommendation or follow-up, and the root's disposition. After a valid inspected
result, the root may route only its research or brainstorming follow-up to a Luna or
Terra subagent outside consultation, synthesize it, and optionally start a fresh
separately receipted consultation. An unavailable result cannot be rescued by that work.
Receipts summarize verified evidence; the distinct Codex consultation thread is the
inspectable detailed runtime record. Progress stays on stderr; successful stdout is
one verified JSON object. A skip or unavailable preflight emits only
`ADVISOR DECISION`, with no call/result receipt and no transport invocation.

The companion installer adds only the two exact current advisor roles. During upgrade it
recoverably retires byte-exact known historical implementation/review roles without
editing Codex configuration or overwriting modified or unsafe files. It also retires
exact Advisor 1.1.0 role files to `.retired-v1.1.0` paths before installing the
risk-described 1.3.0 roles. Later exact 1.3.0 generations use separate
`.retired-v1.3.0` and `.retired-v1.3.0-zero-tool` paths; modified, dual, or
colliding states fail closed.

## Verify

```sh
sh plugins/advisor/scripts/verify.sh --static
```

The no-argument verifier is byte-identical to `--static` and does not start Codex or
use the network. Live trigger evaluation is a separate attended workflow documented
in [consultation operations](plugins/advisor/skills/consultation/references/operations.md).
That workflow keeps the parent's authenticated Codex home, uses two isolated temporary
project/child-runtime fixtures, and intentionally expects `route: unavailable` because
ephemeral runs have no persisted parent rollout. Deterministic persisted fixtures prove
the read-only consult path separately.

For a local, read-only aggregate audit of recent advisor runtime evidence:

```sh
sh plugins/advisor/scripts/advisor-audit.sh --window-hours 24
```

It reports only redacted counts and totals, with stderr progress before session
enumeration and parsing. Use `--since`/`--until` for an explicit RFC3339 window or
`--sessions-dir` for an isolated fixture. Schema v2 exposes exact `consult`, `skip`,
and `unavailable` counts at top level, identifies current advisor child sessions from
full-file metadata before windowing activity, and reports deduplicated parent spawn
completion evidence separately with explicit availability. Current parent spawn
requests and role-free subagent lifecycle activity are corroborating aggregate counts
only; neither can establish selected role or completion. It never changes sessions or
configuration.

## Origin and maintenance

This fork is maintained by David Schmidt / Zero Delta LLC. It derives from Daniel
McAteer's upstream [Sol Advisor](https://github.com/DannyMac180/sol-advisor) at audited base
`37b75cad535abdd46531f0227483a8842d045ab8`; see [NOTICE.md](NOTICE.md). Daniel's MIT
copyright remains in [LICENSE](LICENSE).

## Repository hygiene

`HISTORY.md`, `TASKS.md`, `verifications/`, and `.logs/` are local delivery and audit
artifacts and are excluded from the public repository. The committed contract is
defined by this README, [SPEC.md](SPEC.md), [INVARIANTS.md](INVARIANTS.md), the
plugin source, and the license/provenance files.
