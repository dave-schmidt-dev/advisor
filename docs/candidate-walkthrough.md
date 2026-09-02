# Candidate fresh-host walkthrough

## Clean host

A clean host is a new, empty `CODEX_HOME` root. Advisor resolves its Codex root
from `CODEX_HOME`, so this is sufficient to isolate the candidate without needing
a second machine. Do not copy `auth.json`, credentials, tokens, or any existing
Codex-root contents into it. The new root has no credentials: sign in again inside
that root. That re-authentication is the point of the check because it proves the
documented local-runtime prerequisite is real.

Use a temporary root for the attended session, for example:

```sh
export CODEX_HOME="$(mktemp -d)"
codex
```

Finish the session normally, then remove only that temporary directory when the
owner no longer needs it.

For a guided version of this flow, run the repository helper from a fresh terminal:

```sh
sh public-release/run-clean-host-receipt.sh
```

It creates and keeps a fresh `CODEX_HOME`, verifies the local tracked tree is clean,
derives the current `HEAD` SHA, runs the marketplace add against that SHA,
runs and verifies the owner-controlled ChatGPT login flow, pauses for one
consultation, resolves the installed plugin directory, checks the installed and source
manifest versions match, and binds external evidence to the fresh-root sessions
before `verify-clean-host.sh` captures. It never runs the consultation or removes
`CODEX_HOME`;
the helper prints the manual removal command.
Save the observed runtime/launcher JSON outside the fresh root when the helper asks
for its path.

## Install the candidate

Register the marketplace, then install its Advisor entry. The marketplace itself may
be added either from the Git repository shorthand or from a local clone; within that
marketplace the plugin source is the local path `./plugins/advisor`, so the plugin
content always comes from the marketplace checkout rather than from a separate
download.

```sh
codex plugin marketplace add dave-schmidt-dev/advisor --ref "$(git rev-parse HEAD)"
codex plugin add advisor@advisor
```

To exercise a clone you already have on disk, replace the first command with
`codex plugin marketplace add /absolute/path/to/advisor`.

Installing the plugin does not install the advisor role profiles. Run the installer
that ships with the installed copy, resolving its directory from the plugin list
rather than assuming a path:

```sh
plugin_dir="$(codex plugin list --json | jq -r '.installed[] | select(.pluginId == "advisor@advisor") | .source.path')"
test -n "$plugin_dir" && test "$plugin_dir" != null && test -d "$plugin_dir" \
  && sh "$plugin_dir/scripts/install-agents.sh"
```

Start a new Codex CLI or Codex desktop thread after installation so it discovers the
skill and role files from the fresh root.

## Prerequisites and recovery

The complete compatibility matrix is in
[`public-directory-compatibility.md`](public-directory-compatibility.md). The
fresh-host path requires the following conditions. Each missing condition produces
`route: unavailable`; no consultation transport runs.

| Required condition | Why it matters |
| --- | --- |
| Codex CLI or Codex desktop | Provides the supported local Codex runtime. |
| `jq` | Reads and validates the runtime evidence. |
| POSIX shell | Runs the fixed launcher and validators. |
| Persisted Codex session rollout | Supplies inspectable runtime provenance. |
| Current-thread identity in `CODEX_THREAD_ID` | Identifies the parent; there is no session-ID fallback. |
| The `require_escalated` launcher boundary | Permits only the fixed installed launcher to start the child. |

## What to observe

A correct consultation crosses the narrow `require_escalated` launcher boundary,
starts a distinct read-only child, and uses an advisor with zero tools. The runtime
evidence must report the actual transport, model, effort, and sandbox policy; do not
edit those values to make a check pass. The captured receipt redacts thread identifiers
and stores only `agent_role`, `transport`, `model`, `effort`,
`sandbox_policy_type`, and `permission_profile_type`.

## Candidate-current acceptance record

### Candidate version

The public-listing identity and installed plugin manifest are version `1.3.4`.
The helper pins the marketplace candidate to local `HEAD` and verifies installed
manifest version parity before capture. The candidate content digest is recorded in
[`release-notes-draft.md`](release-notes-draft.md). Before submission, the release
owner runs `sh public-release/freeze-candidate.sh --check` and pins the reviewed
commit with the documented `v1.3.4` tag.

### Host preflight

The attended clean-host run created an empty `CODEX_HOME`, completed and verified
the fresh-root ChatGPT login, registered the `advisor` marketplace, installed the
resolved plugin copy, and installed its two advisor profiles. This host preflight
was completed before the consultation; it did not reuse a prior Codex root or copy
credentials into the fresh root.

### Eligible consultation

One eligible consultation then completed in a new fresh-root Codex session. Its
captured allowlisted runtime receipt identifies `advisor-terra` with `gpt-5.6-terra` or
`advisor-sol` with `gpt-5.6-sol`, `codex-exec` transport, high effort, a read-only
sandbox, and a managed permission profile. The receipt is runtime evidence only:
it intentionally does not preserve conversation content or session identifiers.

### Unavailable evidence

No unavailable evidence was produced by this successful attended run. The supported
failure contract is nevertheless part of the acceptance record: a missing host
prerequisite, unsupported surface, incomplete runtime evidence, or a non-read-only
child produces `route: unavailable` and starts no consultation transport. Receipt
capture also rejects incomplete or non-read-only evidence without replacing a
previous valid receipt.

## Capture the owner receipt

After one attended consultation, save the observed runtime-inspector JSON or the
launcher result JSON that contains its `runtime` object. The helper parses only
`thread_id`, `parent_thread_id`, `agent_role`, and `model` from that file, binds
those identities to the fresh `CODEX_HOME` sessions via
`inspect-agent-runtime.sh`, and captures the inspector-emitted runtime JSON to the
intended evidence path explicitly:

The standalone capture command below validates the supplied runtime evidence file only;
the identity binding to fresh-root sessions is performed by
`public-release/run-clean-host-receipt.sh`:

```sh
sh public-release/verify-clean-host.sh --capture \
  docs/clean-host-smoke-receipt.json \
  /path/to/attended-runtime-evidence.json
```

The capture command has no default destination. It copies only observed allowlisted
fields into a temporary file, applies the clean-host predicate to that file, and moves
it into place only when the predicate holds. No new receipt replaces an existing valid
receipt; if the observed child was not read-only or evidence is incomplete, the
command exits nonzero and the previously stored receipt remains unchanged.
