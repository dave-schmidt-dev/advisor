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
- [Release v1.3.3](https://github.com/dave-schmidt-dev/advisor/releases/tag/v1.3.3)

## Development

```sh
sh plugins/advisor/scripts/verify.sh --static
```

The implementation contract is in the [plugin skill](plugins/advisor/skills/consultation/SKILL.md),
[SPEC.md](SPEC.md), and [INVARIANTS.md](INVARIANTS.md).

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
