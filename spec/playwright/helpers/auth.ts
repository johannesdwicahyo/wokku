import type { Page } from "@playwright/test";

// Sign in via the /dev/login Rack endpoint (config/initializers/
// omniauth_dev_login.rb). Returns once the session cookie is set.
// Requires WOKKU_ENABLE_DEV_LOGIN=1 on the Rails server in CI envs.
export async function signInAsDev(page: Page, email = "playwright@wokku.cloud"): Promise<void> {
  const response = await page.goto(`/dev/login?email=${encodeURIComponent(email)}`, {
    waitUntil: "domcontentloaded",
  });
  if (!response || !response.ok()) {
    throw new Error(
      `/dev/login returned ${response?.status() ?? "no response"}. ` +
        `Set WOKKU_ENABLE_DEV_LOGIN=1 on the Rails server, or run in dev/test env.`
    );
  }
}

export async function signInAsAdmin(page: Page): Promise<void> {
  const response = await page.goto("/dev/login?email=playwright-admin@wokku.cloud&admin=1", {
    waitUntil: "domcontentloaded",
  });
  if (!response || !response.ok()) {
    throw new Error(`/dev/login (admin) returned ${response?.status() ?? "no response"}.`);
  }
}
