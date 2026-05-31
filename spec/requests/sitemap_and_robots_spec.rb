require "rails_helper"

RSpec.describe "Sitemap + robots.txt", type: :request do
  describe "GET /sitemap.xml" do
    it "returns the generated sitemap" do
      get "/sitemap.xml"
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/xml").or include("text/xml")
    end

    it "lists every canonical public marketing page" do
      get "/sitemap.xml"
      body = response.body
      %w[/pricing /faq /changelog /contact /deploy /privacy /terms /refund].each do |path|
        expect(body).to include("https://wokku.cloud#{path}")
      end
      # Root URL appears too (auto-added by sitemap_generator)
      expect(body).to include("<loc>https://wokku.cloud</loc>")
    end

    it "emits hreflang alternates per URL for en + id" do
      get "/sitemap.xml"
      expect(response.body).to include('hreflang="en"')
      expect(response.body).to include('hreflang="id"')
      expect(response.body).to include("?locale=en")
      expect(response.body).to include("?locale=id")
    end

    it "excludes per-spike /lp/* paths (paid-ad-only, noindex'd)" do
      get "/sitemap.xml"
      %w[/lp/zero-ops /lp/ai-native /lp/flat-price /lp/one-click-apps].each do |lp|
        expect(response.body).not_to include("https://wokku.cloud#{lp}")
      end
    end

    it "excludes authenticated paths" do
      get "/sitemap.xml"
      expect(response.body).not_to include("/dashboard")
      expect(response.body).not_to include("/admin")
      expect(response.body).not_to include("/users/sign_in")
    end
  end

  describe "GET /robots.txt" do
    it "returns 200" do
      get "/robots.txt"
      expect(response).to have_http_status(:ok)
    end

    it "disallows authenticated and ad-only paths" do
      get "/robots.txt"
      %w[/dashboard /admin /users/sign_in /users/sign_up /lp/].each do |path|
        expect(response.body).to include("Disallow: #{path}")
      end
    end

    it "references the sitemap" do
      get "/robots.txt"
      expect(response.body).to include("Sitemap: https://wokku.cloud/sitemap.xml")
    end

    it "applies the policy to all user-agents" do
      get "/robots.txt"
      expect(response.body).to include("User-agent: *")
    end
  end
end
