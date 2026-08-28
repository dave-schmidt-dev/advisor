# Advisor

Advisor adds one automatic, read-only consultation before a
material technical decision. It does not implement, route implementation, or perform
final review. The root agent owns every decision and records whether advice was
accepted, modified, or rejected.

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

Before implementation, the root emits `ADVISOR DECISION` with `consult` or `skip`, a
task-specific reason, and a bounded question when consulting. A valid consult uses
exactly one model-pinned role selected by decision risk. Standard consultation,
including generic advisor requests, uses `advisor-terra` (`gpt-5.6-terra` / High).
Specialist consultation uses `advisor-sol` (`gpt-5.6-sol` / High) only for an
unresolved security or trust boundary, an irreversible migration or data-loss
decision, or a credible unresolved High-severity disagreement. Security adjacency
and project importance alone do not qualify; a borderline role choice uses Terra.
The parent model is irrelevant, and the parent does not pass a model override. The
completed spawn event must prove the exact selected role/model pair, effort, and
distinct receiver thread. If it does not,
evidence is unavailable and the consult route blocks rather than continuing
independently.

The companion installer adds only the two exact current advisor roles. During upgrade it
recoverably retires byte-exact known historical implementation/review roles without
editing Codex configuration or overwriting modified or unsafe files. It also retires
exact Advisor 1.1.0 role files to `.retired-v1.1.0` paths before installing the
risk-described 1.2.0 roles; modified, dual, or colliding states fail closed.

## Verify

```sh
sh plugins/advisor/scripts/verify.sh --static
```

The no-argument verifier is byte-identical to `--static` and does not start Codex or
use the network. Live trigger evaluation is a separate attended workflow documented
in [consultation operations](plugins/advisor/skills/consultation/references/operations.md).
That workflow keeps the parent's authenticated Codex home, uses two isolated temporary
project/child-runtime fixtures, and accepts consultation identity only from completed
`spawn_agent` events with a receiver thread distinct from the root.

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
