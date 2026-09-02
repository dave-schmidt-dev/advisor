#!/usr/bin/env sh
# Deploy the Codex Advisor public site (site/) to the Opalstack static app.
#
# Target: the `advisor/` subdirectory of the `zerodelta` static app on
# opal18.opalstack.com, served at https://zerodelta.dev/advisor/.
# Requires the `zerodelta` host alias in ~/.ssh/config and an authorized key.
#
# site/ contains only deployable content; test tooling lives in web-tests/.
#
# Usage:
#   ./deploy-site.sh            # deploy
#   ./deploy-site.sh --dry-run  # show what would change, transfer nothing

set -eu

REMOTE="zerodelta"
APP_DIR="apps/zerodelta/advisor"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)/site"

DRY=""
if [ "${1:-}" = "--dry-run" ]; then
    DRY="--dry-run"
    printf 'DRY RUN — no files will be transferred.\n\n' >&2
fi

# The Opalstack app owns its own directory. Refuse to deploy unless the
# control panel has provisioned it, rather than creating a stray tree that the
# panel does not know about.
if ! ssh -o BatchMode=yes "$REMOTE" "test -d ~/apps/zerodelta"; then
    printf 'error: ~/apps/zerodelta does not exist on %s.\n' "$REMOTE" >&2
    printf 'Create the `zerodelta` static app in the Opalstack control panel first.\n' >&2
    exit 1
fi

# site/assets/logo.svg is a copy of the submission logo so the deployable tree
# is self-contained. A copy can drift from its original silently, so refuse to
# publish a stale one rather than shipping two different logos.
if ! cmp -s "$SRC_DIR/assets/logo.svg" "$SRC_DIR/../assets/public-logo.svg"; then
    printf 'error: site/assets/logo.svg differs from assets/public-logo.svg.\n' >&2
    printf 'Reconcile them before deploying.\n' >&2
    exit 1
fi

printf 'Deploying %s -> %s:~/%s\n' "$SRC_DIR" "$REMOTE" "$APP_DIR" >&2

# Opalstack's nginx runs as a separate user, so the published tree must be
# world-readable. Repository files can be mode 600 locally; without an
# explicit --chmod the deploy silently produces a 403.
rsync -avz --delete --chmod=D755,F644 $DRY --exclude=".DS_Store" "$SRC_DIR/" "$REMOTE:$APP_DIR/"

printf '\nDeployed. Verify with:\n' >&2
printf '  curl -sSI https://zerodelta.dev/advisor/\n' >&2
