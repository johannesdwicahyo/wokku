# Sitemap config (see https://github.com/kjvarga/sitemap_generator).
# Re-emit via:  bundle exec rake sitemap:refresh:no_ping
#
# Per the spec §6 SEO requirements, this sitemap:
#   - includes every canonical public marketing page in EN + ID
#   - excludes /lp/* per-spike paid-ad pages (they're noindex'd anyway)
#   - excludes /dashboard, /admin, /users/* (also disallowed in robots.txt)
#   - emits hreflang alternates per URL so Google can serve the right
#     locale for each page

SitemapGenerator::Sitemap.default_host = "https://wokku.cloud"
SitemapGenerator::Sitemap.public_path  = "public/"
SitemapGenerator::Sitemap.compress     = false # plain XML — easier to inspect

SitemapGenerator::Sitemap.create do
  PUBLIC_PATHS = %w[
    /
    /pricing
    /faq
    /changelog
    /contact
    /deploy
    /privacy
    /terms
    /refund
  ].freeze

  PUBLIC_PATHS.each do |path|
    add path,
        changefreq: "weekly",
        alternates: [
          { href: "https://wokku.cloud#{path}?locale=en", lang: "en" },
          { href: "https://wokku.cloud#{path}?locale=id", lang: "id" }
        ]
  end

  # NOTE: /lp/zero-ops, /lp/ai-native, /lp/flat-price, /lp/one-click-apps
  # (built in Phase 1 task 18) are deliberately omitted. Those are paid-
  # ad-only landings; they emit <meta name="robots" content="noindex">
  # and are disallowed in robots.txt. Including them would dilute the
  # canonical / for the same query terms.
end
