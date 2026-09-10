# Marketplace release process

1. Update the target-version marketplace Short Description and Long Description in
   `docs/public-listing.md`, and update all relevant website, product, privacy,
   support, and terms copy. The source manifest description may remain generic; the
   public listing text is the marketplace copy.
2. Run local tests and review, then prepare the dated candidate-current
   screen-by-screen walkthrough. The owner reviews it before deployment.
3. Deploy the site with `./deploy-site.sh`, then verify that the public pages,
   sitemap, and deployable assets match the local bytes. The gate uses an explicit
   inventory, so add each new deployable site file to the gate before release.
4. Commit and push the exact source for the target version.
5. Create or update the matching GitHub release `vVERSION` with accurate release
   notes and the exact same marketplace ZIP. Separately verify that the tag resolves
   to the intended source and that the downloaded GitHub asset SHA-256 equals the
   marketplace ZIP SHA-256. This GitHub verification is a required release step;
   `public-release/verify-upload-ready.sh` does not perform it.
6. Immediately before the owner uploads the exact existing candidate ZIP, run:

   ```sh
   public-release/verify-upload-ready.sh [--json] ARCHIVE.zip
   ```

   The optional `--json` flag comes before the ZIP path. `UPLOAD READY` is valid only
   for that run and that archive; there is no offline or prior-receipt bypass.
7. Only after the fresh upload-readiness gate passes may the candidate be described
   as upload-ready or the marketplace upload be authorized. The owner
   pastes/confirms marketplace metadata; confirm the support URL separately.

Repeat this sequence for every version. Release completion requires the website,
descriptions, matching GitHub release, and owner-confirmed marketplace publication;
no previous receipt substitutes for current evidence. A built ZIP remains
candidate-only until this current gate passes. Do
not rebuild or alter a plugin ZIP solely because external listing text changed.

The upload-readiness script validates only the ZIP, listing, and website. GitHub
release creation and the tag/source/asset verification above are separate required
steps and are not automated by that script.
