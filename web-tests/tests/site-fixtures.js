// Shared fixtures for the Codex Advisor site specs.
const fs = require('node:fs');
const nodePath = require('node:path');
const { test } = require('@playwright/test');

// The global header comes from the Zero Delta site shell, published by the
// zero-delta-dev repository at https://zerodelta.dev/assets/. The test server
// only serves ../site, so serve these exact root-absolute shell files from the
// sibling zero-delta-dev checkout (or ZERO_DELTA_SHELL_DIR).
const SHELL_DIR = process.env.ZERO_DELTA_SHELL_DIR
  || nodePath.resolve(__dirname, '../../../zero-delta-dev/assets');
const SHELL_FILES = {
  '/assets/site-shell.css': ['site-shell.css', 'text/css'],
  '/assets/zd-mark.png': ['zd-mark.png', 'image/png'],
};


/** Serve the root-absolute Zero Delta shell files from the sibling checkout. */
function useZeroDeltaShell() {
  test.beforeEach(async ({ page }) => {
    for (const [file] of Object.values(SHELL_FILES)) {
      if (!fs.existsSync(nodePath.join(SHELL_DIR, file))) {
        throw new Error(
          `Zero Delta shell file missing: ${nodePath.join(SHELL_DIR, file)}. ` +
          'Check out zero-delta-dev beside this repository or set ZERO_DELTA_SHELL_DIR.'
        );
      }
    }
    await page.route(
      (url) => Object.hasOwn(SHELL_FILES, url.pathname),
      async (route) => {
        const [file, contentType] = SHELL_FILES[new URL(route.request().url()).pathname];
        await route.fulfill({ path: nodePath.join(SHELL_DIR, file), contentType });
      }
    );
  });
}

const PAGES = [
  { path: '/', title: /Codex Advisor/, heading: /Codex Advisor/ },
  { path: '/privacy/', title: /Privacy Policy/, heading: /Privacy Policy/ },
  { path: '/terms/', title: /Terms of Service/, heading: /Terms of Service/ },
  { path: '/support/', title: /Support/, heading: /Support & Troubleshooting/ },
];

module.exports = { PAGES, SHELL_FILES, useZeroDeltaShell };
