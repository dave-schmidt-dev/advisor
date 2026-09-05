// Smoke coverage for the Codex Advisor public site.
//
// The site is static and has no application logic, so these tests assert the
// things that actually break on a static site: a page fails to load, an asset
// 404s, an internal link rots, the claim surface drifts from the validated
// listing, or the layout overflows on a phone.
const { test, expect } = require('@playwright/test');

const PAGES = [
  { path: '/', title: /Codex Advisor/, heading: /Codex Advisor/ },
  { path: '/privacy/', title: /Privacy Policy/, heading: /Privacy Policy/ },
  { path: '/terms/', title: /Terms of Service/, heading: /Terms of Service/ },
  { path: '/support/', title: /Support/, heading: /Support & Troubleshooting/ },
];

/** Collect console errors and failed network requests for one navigation. */
function watchFailures(page) {
  const failures = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') failures.push(`console: ${msg.text()}`);
  });
  page.on('pageerror', (err) => failures.push(`pageerror: ${err.message}`));
  page.on('requestfailed', (req) => failures.push(`requestfailed: ${req.url()}`));
  page.on('response', (res) => {
    if (res.status() >= 400) failures.push(`http ${res.status()}: ${res.url()}`);
  });
  return failures;
}

/** Return rendered body copy with markup-only whitespace collapsed. */
async function bodyText(page) {
  return (await page.locator('body').innerText()).replace(/\s+/g, ' ').trim();
}

for (const { path, title, heading } of PAGES) {
  test(`${path} renders without errors`, async ({ page }, testInfo) => {
    const failures = watchFailures(page);

    await page.goto(path);

    await expect(page).toHaveTitle(title);
    await expect(page.locator('h1')).toHaveText(heading);
    await expect(page.locator('header.site-header')).toBeVisible();
    await expect(page.locator('footer.site-footer')).toBeVisible();
    await page.screenshot({ path: testInfo.outputPath('page.png'), fullPage: true });
    expect(failures).toEqual([]);
  });

  test(`${path} loads its stylesheet`, async ({ page }) => {
    await page.goto(path);
    // The dark theme comes from the external stylesheet. If it 404s the page
    // still renders, so assert a computed value rather than the request.
    const bg = await page.evaluate(() =>
      getComputedStyle(document.body).backgroundColor
    );
    expect(bg).toBe('rgb(13, 17, 23)');
  });

  test(`${path} has no horizontal overflow`, async ({ page }) => {
    await page.goto(path);
    const overflow = await page.evaluate(() => {
      const el = document.documentElement;
      // Allow scrollable code blocks and tables; only the page itself must fit.
      return el.scrollWidth - el.clientWidth;
    });
    expect(overflow).toBeLessThanOrEqual(1);
  });
}

test('every internal link resolves', async ({ page, request }) => {
  const seen = new Set();

  for (const { path } of PAGES) {
    await page.goto(path);
    const hrefs = await page.locator('a[href]').evaluateAll((els) =>
      els.map((el) => el.getAttribute('href'))
    );

    for (const href of hrefs) {
      if (!href || href.startsWith('http') || href.startsWith('mailto:')) continue;
      const [target, fragment] = href.split('#');

      if (target) {
        // Links are relative so the tree can be mounted at any path. Resolve
        // against the current page, which is what the browser does.
        const resolved = new URL(target, page.url()).toString();
        if (!seen.has(resolved)) {
          seen.add(resolved);
          const res = await request.get(resolved);
          expect(res.status(), `${href} from ${path}`).toBe(200);
        }
      } else if (fragment) {
        // Same-page anchor: the target element must exist on this page.
        await expect(
          page.locator(`#${fragment}`),
          `#${fragment} on ${path}`
        ).toHaveCount(1);
      }
    }
  }

  expect(seen.size).toBeGreaterThan(0);
});

test('the site tree is relocatable', async ({ page }) => {
  // The site is deployed under /advisor/, not at a domain root, so no link or
  // asset reference may be root-absolute.
  for (const { path } of PAGES) {
    await page.goto(path);
    const refs = await page.evaluate(() =>
      [...document.querySelectorAll('[href], [src]')].map(
        (el) => el.getAttribute('href') || el.getAttribute('src')
      )
    );
    for (const ref of refs) {
      expect(
        ref.startsWith('/'),
        `root-absolute reference on ${path}: ${ref}`
      ).toBe(false);
    }
  }
});

test('every page uses the shared global navigation', async ({ page }) => {
  const expected = [
    ['Home', 'https://zerodelta.dev/'],
    ['Advisor', 'https://zerodelta.dev/advisor/'],
  ];

  for (const { path } of PAGES) {
    await page.goto(path);
    const links = await page.locator('.site-nav a').evaluateAll((items) =>
      items.map((item) => [item.textContent.trim(), item.href])
    );
    expect(links).toEqual(expected);
    const current = await page.locator('.site-nav a[aria-current="page"]').allTextContents();
    expect(current).toEqual(path === '/' ? ['Advisor'] : []);
  }
});

test('canonical URLs point at the deployed path', async ({ page }) => {
  for (const { path } of PAGES) {
    await page.goto(path);
    const canonical = await page
      .locator('link[rel="canonical"]')
      .getAttribute('href');
    expect(canonical).toBe(
      `https://zerodelta.dev/advisor${path === '/' ? '/' : path}`
    );
  }
});

test('shared Zero Delta visual system', async ({ page }) => {
  await page.goto('/');

  const chrome = await page.locator('.site-header').evaluate((header) => {
    const heading = document.querySelector('h2');
    const headerStyle = getComputedStyle(header);
    return {
      background: headerStyle.backgroundColor,
      topRadius: headerStyle.borderTopLeftRadius,
      prefix: heading ? getComputedStyle(heading, '::before').content : '',
    };
  });

  expect(chrome.background).toBe('rgb(15, 20, 28)');
  expect(chrome.topRadius).toBe('28px');
  expect(chrome.prefix).toContain('>');

  const brandPromptMargin = await page.locator('.global-brand').evaluate((brand) =>
    parseFloat(getComputedStyle(brand, '::before').marginRight)
  );
  expect(brandPromptMargin).toBeGreaterThanOrEqual(4);
});

test('landing hero aligns with the shared brand edge', async ({ page }) => {
  await page.goto('/');

  await expect(page.locator('.product-mark')).toHaveCount(0);
  const positions = await page.evaluate(() => ({
    heading: document.querySelector('.hero h1').getBoundingClientRect().x,
    brand: document.querySelector('.global-brand').getBoundingClientRect().x,
  }));

  expect(positions.heading).toBe(positions.brand);
});

test('claim surface matches the validated listing', async ({ page }) => {
  // These claims are load-checked against docs/public-listing.md. Drift here
  // is a directory-submission problem, not a cosmetic one.
  await page.goto('/');
  const body = (await bodyText(page)).toLowerCase();

  expect(body).toContain('documentation v1.4.2');
  expect(body).toContain('automatic read-only advice');
  expect(body).toContain('smart defaults');
  expect(body).toContain('optional models');
  expect(body).toContain('[standard]');
  expect(body).toContain('[specialist]');
  expect(body).toContain('gpt-6-astra');
  expect(body).toContain('gpt-5.6-terra');
  expect(body).toContain('gpt-5.6-sol');
  expect(body).toContain('next consultation');
  expect(body).toContain('no setup conversation or separate canary is required.');
  expect(body).toContain('plugin updates may replace edits to the bundled file.');
  expect(body).not.toContain('advisor-terra');
  expect(body).not.toContain('advisor-sol');
});

test('each route carries the candidate release metadata', async ({ page }) => {
  for (const { path } of PAGES) {
    await page.goto(path);
    await expect(page.locator('meta[name="advisor-release"]')).toHaveAttribute('content', '1.4.2');
  }
});

test('support page uses published directory recovery guidance', async ({ page }) => {
  await page.goto('/support/');
  const support = await bodyText(page);
  const directoryUrl = 'https://chatgpt.com/plugins/plugins_6a984f37e9c88191a2a777998f7b0521';

  expect(support).toContain('official OpenAI Plugins Directory');
  await expect(page.locator(`a[href="${directoryUrl}"]`)).toHaveCount(1);
  expect(support).toContain('reinstall or update');
  expect(support).toContain('start a new Codex thread');
  expect(support).toContain('advisor.toml');
  expect(support).toContain('two directories above');
  expect(support).toContain('skills/consultation/SKILL.md');
  expect(support).toContain('Edit that bundled file in place');
  expect(support).toContain('do not copy it');
  expect(support).toContain('Invalid TOML');
  expect(support).toContain('unsupported-model');
  expect(support).toContain('does not silently fall back');
  expect(support).toContain('may replace edits');
  expect(support).toContain('ADVISOR DECISION');
  expect(support).toContain('ADVISOR CALL');
  expect(support).toContain('ADVISOR RESULT');
  expect(support).not.toContain('install-agents.sh');
  expect(support).not.toContain('sh plugins/advisor/');
});

test('terms identify the current developer and maintainer', async ({ page }) => {
  await page.goto('/terms/');
  const terms = await bodyText(page);

  expect(terms).toContain('Developer and maintainer: David Schmidt / Zero Delta LLC');
  expect(terms).not.toContain('Daniel McAteer');
  expect(terms).not.toContain('Fork maintainer');
});

test('public boundary and installation language are exact and the cursor is removed', async ({ page }) => {
  await page.goto('/');
  const landing = await bodyText(page);

  expect(landing).toContain('Consultations send bounded packets through your own authenticated Codex/OpenAI account; Zero Delta operates no relay, hosted backend, or intermediary service.');
  expect(landing).toContain('The consultation child is verified read-only and tool-free. Direct invocation of installed advisor profiles is unsupported.');
  const directoryUrl = 'https://chatgpt.com/plugins/plugins_6a984f37e9c88191a2a777998f7b0521';
  await expect(page.locator(`a[href="${directoryUrl}"]`)).toHaveCount(2);
  expect(landing).toContain('Codex Advisor is available in the official OpenAI Plugins Directory.');
  expect(landing).toContain('Install it there, then start a new Codex thread so Advisor is available to the session.');
  expect(landing).not.toContain('codex plugin marketplace add');
  expect(landing).not.toContain('codex plugin add');
  expect(landing).not.toContain('plugin_dir');
  expect(landing).not.toContain('install-agents.sh');
  expect(landing).not.toContain('custom roles');
  await expect(page.locator('.cursor')).toHaveCount(0);

  await page.goto('/privacy/');
  const privacy = (await bodyText(page)).toLowerCase();
  expect(privacy).toContain('local integration. the plugin runs from your own codex installation. it has no zero delta-hosted service or remote backend; bounded consultation packets are sent through your authenticated codex/openai account.');
  expect(privacy).toContain('read-only, zero-tool child. advisor child processes run in a forced read-only sandbox with no tools enabled. they cannot make tool calls or modify local files; the codex runtime still sends the bounded consultation packet directly to openai through your authenticated account.');
  expect(privacy).not.toContain('local execution.');
  expect(privacy).not.toContain('zero-tool sandboxing.');
  expect(privacy).toContain('no zero delta relay. consultation packets are sent directly through your authenticated codex/openai account. zero delta receives no packets, runs no proxy, and collects no telemetry.');
  expect(privacy).toContain('effective date: 5 september 2026');
  expect(privacy).toContain('live');
  expect(privacy).toContain('advisor.toml');
  expect(privacy).toContain('advanced settings and model-catalog data');
  expect(privacy).toContain('content-free usage journal is disabled by default');
  expect(privacy).toContain('operational metadata and aggregate usage counters only');
  expect(privacy).toContain('no consultation packets and no response content');
  expect(privacy).toContain('older than 30 days');
  expect(privacy).toContain('no background deletion service');
  expect(privacy).toContain('uninstalling the plugin may leave user state and session logs behind');
  expect(privacy).toContain('optional astra');
  expect(privacy).not.toContain('offline inference');
  expect(privacy).not.toContain('all consultation data resides solely');
  expect(privacy).not.toContain('no third-party transmission');
});

test('terms describe configured model responsibility and preserve legal terms', async ({ page }) => {
  await page.goto('/terms/');
  const terms = await bodyText(page);

  expect(terms).toContain('Effective date: 5 September 2026');
  expect(terms).toContain('models and effort configured in the bundled');
  expect(terms).toContain('Terra/high and Sol/high as defaults');
  expect(terms).toContain('optional Astra');
  expect(terms).toContain('OpenAI usage, quotas, and fees');
  expect(terms).toContain('update or reinstall may replace those edits');
  expect(terms).toContain('MIT License');
  expect(terms).toContain('AS IS');
  expect(terms).toContain('Limitation of liability');
  expect(terms).toContain('Commonwealth of Virginia');
});

test('every MCP or hosted-service mention carries its negation', async ({ page }) => {
  // The plugin ships no MCP server and no hosted service. A public page that
  // mentions either without negating it is a false capability claim.
  const NEGATED = /(no|without|not?\s+(provide|support)|unsupported|out of scope)/i;

  for (const { path } of PAGES) {
    await page.goto(path);
    const text = await page.locator('body').innerText();

    for (const line of text.split('\n')) {
      if (!/\bMCP\b|hosted service/i.test(line)) continue;
      expect(NEGATED.test(line), `unnegated claim on ${path}: ${line.trim()}`).toBe(true);
    }
  }
});

test('legal pages state the resolved owner values, not placeholders', async ({ page }) => {
  for (const path of ['/privacy/', '/terms/', '/support/']) {
    await page.goto(path);
    const text = await page.locator('body').innerText();

    expect(text, `${path} still has a draft placeholder`).not.toContain('OWNER-PROVIDED');
    expect(text).toContain('advisor@zerodelta.dev');
  }
});
