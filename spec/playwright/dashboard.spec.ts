import { test, expect } from "@playwright/test";
import { signInAsDev } from "./helpers/auth";

// Visual regression for the dashboard surfaces. New baselines bake
// the first time these run (--update-snapshots); subsequent CI runs
// diff against them with a 1% pixel tolerance (playwright.config.ts).
//
// Why these URLs:
//   - /dashboard/apps        — the workspace home (Phase 2 D2)
//   - /dashboard/templates   — gallery (Phase 1 + 5)
//   - /dashboard/billing     — Phase 4 invoice billing
//   - /dashboard/profile     — settings hub (Phase 2 D1)
// Each captured at 1280px desktop + iPhone 14 mobile.

test.describe("Dashboard visual regression", () => {
  test.beforeEach(async ({ page }) => {
    await signInAsDev(page);
  });

  const pages: Array<{ name: string; path: string }> = [
    { name: "apps-index",     path: "/dashboard/apps" },
    { name: "templates",      path: "/dashboard/templates" },
    { name: "billing",        path: "/dashboard/billing" },
    { name: "profile",        path: "/dashboard/profile" },
  ];

  for (const { name, path } of pages) {
    test(`renders ${name}`, async ({ page }) => {
      await page.goto(path, { waitUntil: "domcontentloaded" });
      // Wait for any lazy Turbo frames to settle.
      await page.waitForTimeout(400);
      await expect(page).toHaveScreenshot(`${name}.png`, { fullPage: true });
    });
  }
});
