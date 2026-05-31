import { test, expect } from "@playwright/test";

// Visual regression for public pages. Reuses the existing Phase 1
// baselines under spec/visual-baselines/phase1/ — Phase 3 backlog
// #16 (those 12 PNGs were captured manually and have had no CI
// comparator since).
//
// Playwright snapshot naming: <test-file>-snapshots/<test-name>-<project>.png
// To consume the existing Phase 1 PNGs without renaming, we point
// `snapshotDir` at spec/visual-baselines and use a flat naming
// convention via the second arg to toHaveScreenshot.

test.describe("Public page visual regression", () => {
  const pages: Array<{ name: string; path: string }> = [
    { name: "landing",            path: "/" },
    { name: "pricing",            path: "/pricing" },
    { name: "lp-zero-ops",        path: "/lp/zero-ops" },
    { name: "lp-ai-native",       path: "/lp/ai-native" },
    { name: "lp-flat-price",      path: "/lp/flat-price" },
    { name: "lp-one-click-apps",  path: "/lp/one-click-apps" },
  ];

  for (const { name, path } of pages) {
    test(`renders ${name}`, async ({ page }) => {
      await page.goto(path, { waitUntil: "domcontentloaded" });
      // Lazy turbo frames on landing fire on scroll; trigger them
      // explicitly so the screenshot captures the full assembled page.
      await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
      await page.waitForTimeout(800);
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.waitForTimeout(200);
      await expect(page).toHaveScreenshot(`${name}.png`, { fullPage: true });
    });
  }
});
