# Codex Advisor

Codex Advisor automatically adds a fresh, read-only second opinion when Codex
identifies a material technical decision. It cannot change files, run commands,
browse the web, implement work, deploy, or make the final decision.

## Install

Install [**Codex Advisor** from the official Plugins Directory](https://chatgpt.com/plugins/plugins_6a984f37e9c88191a2a777998f7b0521). It requires
**Codex CLI** or **Codex desktop**; generic ChatGPT is not a supported runtime.

Advisor activates automatically for material design, architecture, migration,
security, compatibility, and competing-diagnosis decisions. It leaves factual,
mechanical, and explicitly no-delegation work alone.

## Links

- [Support](https://zerodelta.dev/advisor/support/)
- [Privacy Policy](https://zerodelta.dev/advisor/privacy/)
- [Terms of Service](https://zerodelta.dev/advisor/terms/)
- [Public listing draft](docs/public-listing.md) and [site walkthrough](docs/site-walkthrough.md)

## Development

```sh
sh plugins/advisor/scripts/verify.sh --static
```

The implementation contract is in the [plugin skill](plugins/advisor/skills/consultation/SKILL.md),
[SPEC.md](SPEC.md), and [INVARIANTS.md](INVARIANTS.md).

Before uploading a version, follow [the release process](docs/release-process.md)
and `public-release/verify-upload-ready.sh`: verify its descriptions and matching
live website. A ZIP alone is only a candidate.

## Selection and discovery

New consultations use `--tier standard|specialist`. The installed live file
`advisor.toml`, beside the loaded skill, is authoritative: Standard defaults to
Terra/high and Specialist to Sol/high. Edit its two documented TOML sections and the
next consultation uses the changed pair. No discovery, catalog registration, canary,
state setup, or file copy is required. A future syntactically valid selector is
permitted subject to account/runtime support; changing Specialist to Astra opts into
its higher usage. Plugin updates or reinstalling can replace in-place edits.
Advisor freezes the model, effort, content-digest source revision, transport contract,
and 30–900 second total deadline before launch, so retries do not choose a newer model
or fallback. The legacy `--role advisor-terra` and `--role advisor-sol` aliases remain
fixed Terra/high and Sol/high routes and do not follow `advisor.toml`.

The installed copy includes `scripts/advisor-config.sh`. `show` and `doctor` display
the actual `advisor.toml` pairs, path, and source revision. Its catalog, preset, and
canary commands are retained advanced tools under Codex home; they do not select a
normal `--tier` consultation. `set` and `reset` reject with that guidance, while
`restore` reports that it restores legacy local state only.

The catalog records `codex-cli 0.153.2` only as tested provenance; it is not an
eligibility pin. A CLI update does not invalidate a canary receipt or the built-in
defaults. The transport's runtime identity, effort, read-only, zero-tool, and schema
checks remain the acceptance boundary. That observed CLI's app-server rejects the
isolation flags discovery requires, so refresh safely returns unavailable and leaves
state unchanged; adding a selector is the manual path. It does not establish that a
real model inference has passed. Actual model canaries require explicit usage
authorization and remain pending for this candidate.

The optional content-free usage journal is disabled by default. `journal enable`,
`journal status`, `journal disable`, and `journal clear` control it. On a later journal
write, Advisor prunes records older than 30 days and keeps the bounded local count; it
does not run a background deletion service.

## Response contract

The wrapper accepts model output only as one object matching its installed JSON Schema,
the sole supported wrapper model-output format. Direct/native role invocation is unsupported and is not schema-validated. After
runtime inspection, wrapper-owned semantic validation renders the accepted object as
the canonical eight-line `ADVISOR RESPONSE` receipt. A runtime-valid
response-validation failure exposes only a redacted failure class and field and gets
one fresh corrective retry, with at most two children. Runtime, identity,
isolation, provenance, or tool failures are terminal. Rejected content remains private
to the mode-0700 consultation directory, is never emitted or copied into a retry
prompt, and is removed by unconditional cleanup.
