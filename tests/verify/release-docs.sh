# shellcheck shell=sh
# Sourced by plugins/advisor/scripts/verify.sh; do not run directly.
grep -Fq 'https://github.com/DannyMac180/sol-advisor' "$notice" || fail "NOTICE upstream URL"
grep -Fq '37b75cad535abdd46531f0227483a8842d045ab8' "$notice" || fail "NOTICE base"
grep -Fq 'David Schmidt / Zero Delta LLC' "$notice" || fail "NOTICE maintainer"
grep -Fq 'Daniel McAteer' "$notice" || fail "NOTICE original author"
grep -Fq 'Copyright (c) 2026 Daniel McAteer' "$license" || fail "LICENSE copyright"
if grep -Eqi 'substack|attentionheads' "$readme"; then fail "README retains Substack promotion"; fi
for phrase in 'automatic' 'read-only' 'cannot' 'Plugins Directory' 'Codex CLI' 'Codex desktop' 'Privacy Policy' 'Terms of Service'; do grep -Fqi "$phrase" "$readme" || fail "README guidance omits: $phrase"; done
for document in "$operations" "$repo_dir/SPEC.md" "$repo_dir/INVARIANTS.md"; do
  for phrase in 'ADVISOR CALL' 'ADVISOR RESULT' 'unavailable' 'blocked' 'distinct Codex consultation'; do
    grep -Fqi "$phrase" "$document" || fail "lifecycle documentation omits $phrase: $document"
  done
done
pass "customer README, repository attribution, and lifecycle documentation parity"

for document in "$readme" "$model_doc" "$walkthrough" "$operations"; do
  grep -Fqi 'Codex home' "$document" || fail "configuration state location missing: $document"
done
for phrase in \
  'gpt-6-astra' 'catalog presence is documentation' 'not an entitlement' \
  'models test MODEL --effort EFFORT --authorize-usage --parent-thread THREAD_ID' \
  '0.153.2' 'safe-unavailable' 'no background deletion service' \
  'prunes records older than 30 days' 'transport contract' 'does not trigger a consultation' \
  'configuration/catalog' \
  'optional content-free usage journal' 'automatic Terra/Sol defaults' \
  'separate explicit-only' 'Astra' \
  '1.4.4 deployment record' 'not yet deployed'; do
  grep -Fqi "$phrase" "$model_doc" || fail "model configuration documentation omits: $phrase"
done
grep -Eq '^Candidate content digest: `[0-9a-f]{64}`\.$' "$release_notes" || fail "candidate digest placeholder missing"
[ "$(grep -Ec '^Candidate content digest: `[0-9a-f]{64}`\.$' "$release_notes")" -eq 1 ] || fail "candidate digest must appear exactly once"
grep -Fqi 'historical archive fingerprint' "$release_notes" || fail "historical 1.3.4 fingerprint label missing"
grep -Fqi 'Repository-root documentation is not in the ZIP' "$release_notes" || fail "ZIP boundary documentation missing"
grep -Fqi 'Mocked' "$walkthrough" || fail "walkthrough must label mocked evidence"
for phrase in \
  'owner approved the website walkthrough and deployment' \
  'website, privacy, and terms bytes are deployed and live-byte verified'; do
  grep -Fqi "$phrase" "$walkthrough" || fail "walkthrough omits post-approval deployment evidence: $phrase"
done
pass "1.4 model, privacy, candidate walkthrough, release-history, and ZIP-boundary documentation"
