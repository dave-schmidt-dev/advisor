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
4. Immediately before the owner uploads the exact existing candidate ZIP, run:

   ```sh
   public-release/verify-upload-ready.sh [--json] ARCHIVE.zip
   ```

   The optional `--json` flag comes before the ZIP path. `UPLOAD READY` is valid only
   for that run and that archive; there is no offline or prior-receipt bypass.
5. Only after this gate passes may the candidate be described as upload-ready or the
   marketplace upload be authorized. The owner pastes/confirms marketplace metadata;
   confirm the support URL separately.

Repeat this sequence for every version. A built ZIP, including the existing 1.4.2
candidate, remains candidate-only until this current gate passes. Do not rebuild or
alter a plugin ZIP solely because external listing text changed.
