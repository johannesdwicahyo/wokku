import { defineConfig, devices } from "@playwright/test";

// Visual regression for public + dashboard pages.
//
// Phase 3 backlog #15 (auth'd Lighthouse + visual regression on
// dashboard) and #16 (pixel-diff CI against the existing Phase 1
// baselines under spec/visual-baselines/phase1/) live in the same
// harness. Both rely on /dev/login (Rack endpoint) for auth — see
// config/initializers/omniauth_dev_login.rb.

export default defineConfig({
  testDir: "./spec/playwright",
  fullyParallel: false,                     // single Rails server = serialize
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: process.env.CI ? "github" : "list",

  expect: {
    // Allow ≤1% pixel difference per screenshot — tolerates font
    // anti-aliasing and similar noise without masking real layout
    // regressions.
    toHaveScreenshot: { maxDiffPixelRatio: 0.01 },
  },

  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || "http://localhost:3000",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    // Hide animations + force reduced motion so screenshots don't
    // capture mid-frame Stimulus animations (motion library).
    reducedMotion: "reduce",
  },

  projects: [
    {
      name: "desktop",
      use: { ...devices["Desktop Chrome"], viewport: { width: 1280, height: 900 } },
    },
    {
      name: "mobile",
      use: { ...devices["iPhone 14"] },
    },
  ],
});
