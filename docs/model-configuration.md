# Advisor model configuration

Advisor's normal consultation configuration is the live `advisor.toml` bundled beside
the installed skill. Repository-root documentation is not part of the ZIP.

## Defaults and evidence

`advisor.toml` has exactly `[standard]` and `[specialist]` sections, each with `model`
and `effort`. Defaults are `gpt-5.6-terra` / `high` and `gpt-5.6-sol` / `high`.
Edit the installed file in place; changes apply to the next `--tier` consultation and
are frozen with a SHA-256 content revision for retries. No local state, discovery,
catalog registration, canary, or file copy is needed. Allowed efforts are `none`,
`minimal`, `low`, `medium`, `high`, `xhigh`, `max`, and `ultra`. Future syntactically
valid model selectors are allowed subject to account/runtime support. Setting
`specialist.model = "gpt-6-astra"` opts into its higher usage. Plugin updates or a
reinstall can replace the edited file.

This grants only permission to attempt the real consultation: the child must still
pass exact runtime model, effort, read-only, zero-tool, and response-schema checks.
Catalog presence is documentation, not an entitlement.

```sh
sh scripts/advisor-config.sh show
sh scripts/advisor-config.sh doctor
```

The helper reports the active path and digest. It never automatically upgrades or
falls back. The old `--role advisor-terra` and `--role advisor-sol` aliases are legacy
fixed pins and do not follow the file.

## Advanced legacy tools

`models refresh`, `models add`, named presets, and synthetic canaries remain isolated
advanced tools. They do not choose normal `--tier` consultations. `set` and `reset`
reject rather than claim to change the active tier; `restore` can restore legacy local
state but explicitly reports that `advisor.toml` remains authoritative.

Only this command uses model capacity:

```sh
sh scripts/advisor-config.sh models test MODEL --effort EFFORT --authorize-usage --parent-thread THREAD_ID
```

`--authorize-usage` is explicit consent for the fixed content-free synthetic canary.
It does not trigger a consultation, and a failed probe remains safe-unavailable.
The catalog, an account's model list, and a saved selection are not consent. Success
records the actual local CLI version (baseline `0.153.2`) as provenance plus the transport contract, but
leaves tier selections unchanged. CLI updates do not stale the receipt; only its exact
model, effort, or transport contract can do so. Local tests mock this path; no real
model canary has been accepted for 1.4.2.

## Local state and privacy

Legacy settings, catalog, canary receipts, and the optional journal live under the
Codex home directory, outside the plugin cache. They do not override the live file.

The content-free usage journal is off by default. `journal enable`, `journal status`,
`journal disable`, and `journal clear` control it. A later journal write prunes records older than 30 days and enforces the bounded count. There is no background deletion service. The journal contains operational metadata and aggregate usage counters, not
decision packets or response content; unavailable counters remain null and aggregate
coverage can be partial.

## Proposed privacy disclosure for owner approval

> Codex Advisor stores local configuration and model-catalog evidence under the Codex
> home directory. Its optional content-free usage journal is disabled by default; when
> enabled, it records bounded operational metadata and aggregate usage counters, prunes
> records during later journal writes after 30 days, and can be disabled or cleared by
> the user. Advisor uses configurable OpenAI models in the local Codex runtime and
> does not operate a Zero Delta relay.

The deployed privacy copy still says consultation data resides solely in session logs
and names only Terra and Sol. Live privacy reconciliation is still a publication prerequisite; it has not been published or owner-approved here.
