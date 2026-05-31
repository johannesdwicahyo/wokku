// Lighthouse CI puppeteer-script: signs in via /dev/login so the
// audit can hit /dashboard/* URLs as a logged-in user.
//
// Used by `.lighthouserc.json` for any URL that begins with
// /dashboard/ or /admin/. Public pages (/, /pricing, /lp/*) skip this.
//
// Requires WOKKU_ENABLE_DEV_LOGIN=1 in the Rails server env (see
// .github/workflows/lighthouse.yml). Without that flag the route 404s.

module.exports = async (browser, { url }) => {
  const isAuthed = url.includes("/dashboard") || url.includes("/admin");
  if (!isAuthed) return; // public page — no sign-in needed

  const origin = new URL(url).origin;
  const email = url.includes("/admin")
    ? "admin-lhci@wokku.cloud"
    : "lhci@wokku.cloud";
  const adminParam = url.includes("/admin") ? "&admin=1" : "";

  const page = await browser.newPage();
  await page.goto(`${origin}/dev/login?email=${email}${adminParam}`, {
    waitUntil: "domcontentloaded",
  });
  await page.close();
};
