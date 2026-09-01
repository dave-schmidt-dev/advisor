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

## Install the candidate

Register the marketplace, then install its Advisor entry. The marketplace itself may
be added either from the Git repository shorthand or from a local clone; within that
marketplace the plugin source is the local path `./plugins/advisor`, so the plugin
content always comes from the marketplace checkout rather than from a separate
download.

```sh
codex plugin marketplace add dave-schmidt-dev/advisor --ref main
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
edit those values to make a check pass.

## Capture the owner receipt

After one attended consultation, save the observed runtime-inspector JSON or the
launcher result JSON that contains its `runtime` object. Then capture the receipt to
the intended evidence path explicitly:

```sh
sh public-release/verify-clean-host.sh --capture \
  docs/clean-host-smoke-receipt.json \
  /path/to/attended-runtime-evidence.json
```

The capture command has no default destination. It copies only observed allowlisted
fields into a temporary file, applies the clean-host predicate to that file, and moves
it into place only when the predicate holds. If the observed child was not read-only,
or if any observed field is missing, the command exits nonzero and writes no receipt
at all: the evidence path is never left holding a file that does not represent a valid
attended consultation.
