// Shared Zero Delta shell coverage: header, navigation, frame, footer and
// the single content inset. The shell CSS and logo are owned by zero-delta-dev.
const { test, expect } = require('@playwright/test');
const { PAGES, useZeroDeltaShell } = require('./site-fixtures');

useZeroDeltaShell();

test('every page uses the shared global navigation', async ({ page }) => {
  const expected = [
    ['Home', 'https://zerodelta.dev/'],
    ['Advisor', 'https://zerodelta.dev/advisor/'],
  ];

  for (const { path } of PAGES) {
    await page.goto(path);
    const links = await page.locator('.global-nav a').evaluateAll((items) =>
      items.map((item) => [item.textContent.trim(), item.href])
    );
    expect(links).toEqual(expected);
    const current = await page.locator('.global-nav a[aria-current="page"]').allTextContents();
    expect(current).toEqual(path === '/' ? ['Advisor'] : []);
  }
});

test('shared Zero Delta visual system', async ({ page }) => {
  await page.goto('/');

  const chrome = await page.locator('.global-header').evaluate((header) => {
    const heading = document.querySelector('h2');
    const headerStyle = getComputedStyle(header);
    return {
      background: headerStyle.backgroundColor,
      topRadius: headerStyle.borderTopLeftRadius,
      prefix: heading ? getComputedStyle(heading, '::before').content : '',
    };
  });

  expect(chrome.background).toBe('rgba(15, 20, 28, 0.88)');
  expect(chrome.topRadius).toBe('28px');
  expect(chrome.prefix).toContain('>');

  const brandPromptMargin = await page.locator('.global-brand').evaluate((brand) =>
    parseFloat(getComputedStyle(brand, '::before').marginRight)
  );
  expect(brandPromptMargin).toBeGreaterThanOrEqual(4);
});

test('shared header is pinned and shows the Zero Delta logo mark', async ({ page }) => {
  for (const { path } of PAGES) {
    await page.goto(path);
    const header = page.locator('header.global-header');
    await expect(header).toHaveCSS('position', 'sticky');
    expect(
      await page.locator('.global-brand .brand-mark').evaluate(
        (image) => image.complete && image.naturalWidth > 0
      ),
      `logo mark on ${path}`
    ).toBe(true);
  }
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

test('every page uses the shared Zero Delta footer inside the shared frame', async ({ page }) => {
  // Same markup and expectations as zero-delta-dev's home-page footer test.
  const expected = [
    ['Home', 'https://zerodelta.dev/'],
    ['Advisor', 'https://zerodelta.dev/advisor/'],
    ['Privacy', 'https://zerodelta.dev/advisor/privacy/'],
    ['Terms', 'https://zerodelta.dev/advisor/terms/'],
    ['Contact', 'mailto:dave@zdelta.dev'],
  ];

  for (const { path } of PAGES) {
    await page.goto(path);
    const footer = page.locator('.site-frame > footer.site-footer');
    await expect(footer, path).toHaveCount(1);
    await expect(footer.locator('.footer-legal')).toHaveText('© 2026 Zero Delta LLC · Virginia');
    const links = await footer.locator('.footer-links a').evaluateAll((items) =>
      items.map((item) => [item.textContent.trim(), item.getAttribute('href')])
    );
    expect(links, path).toEqual(expected);
    // Styles only the shared shell supplies.
    await expect(page.locator('.site-frame')).toHaveCSS('border-bottom-left-radius', '28px');
    await expect(footer.locator('.footer-links')).toHaveCSS('text-transform', 'uppercase');
  }
});

test('header, content and footer share one inset', async ({ page }) => {
  for (const width of [1280, 520, 390]) {
    await page.setViewportSize({ width, height: 800 });
    for (const { path } of PAGES) {
      await page.goto(path);
      const xs = await page.evaluate(() =>
        ['.global-brand', 'h1', 'main h2', '.footer-legal'].map(
          (selector) => document.querySelector(selector).getBoundingClientRect().x
        )
      );
      expect(new Set(xs).size, `${path} at ${width}px: ${xs}`).toBe(1);
    }
  }
});
