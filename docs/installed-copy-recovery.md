# Installed copy recovery

## Identify the installed candidate

For already-installed copies, use the Codex plugin manager to locate the Advisor
plugin directory, then read its `.codex-plugin/plugin.json`. Its `version` field
identifies the exact build metadata; the submitted release identity is `1.3.4`.

## Verify the installed content

Obtain a clean checkout of the candidate pinned by the documented release tag. Copy
the installed plugin directory over `plugins/advisor` in a disposable copy of that
checkout, then run `sh public-release/freeze-candidate.sh --check` from the disposable
copy. A passing check proves the installed package matches the release notes digest.

## Update to a newer candidate

Update the Git marketplace source through the Codex plugin manager, reinstall or
update Advisor, then repeat the identity and digest checks above before resuming use.

## Static-gate failure

If `sh plugins/advisor/scripts/verify.sh --static` fails in a local copy, do not edit
the installed files in place. Reinstall the candidate pinned by the release tag and
run the static gate again; if it still fails, retain the non-sensitive failure output
and report it with the candidate version and recorded digest.
