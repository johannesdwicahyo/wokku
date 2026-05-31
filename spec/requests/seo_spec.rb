require "rails_helper"

RSpec.describe "SEO meta partials", type: :request do
  before do
    %w[free solo pro team].each do |k|
      Plan.find_or_create_by!(key: k) { |p| p.name = k.capitalize }
    end
    Plan.find_by(key: "free").update!(price_usd_cents: 0,    price_idr: 0)
    Plan.find_by(key: "solo").update!(price_usd_cents: 500,  price_idr: 75_000)
    Plan.find_by(key: "pro").update!(price_usd_cents: 1500,  price_idr: 225_000)
    Plan.find_by(key: "team").update!(price_usd_cents: 5000, price_idr: 750_000)
  end

  describe "GET / (landing)" do
    it "renders the per-page <title> (set via content_for in landing.html.erb)" do
      get "/"
      expect(response.body).to match(%r{<title>.*Stop.*babysitting.*servers.*Wokku</title>})
    end

    it "renders the canonical URL" do
      get "/", headers: { "Host" => "wokku.cloud" }
      expect(response.body).to include(%(<link rel="canonical" href="http://wokku.cloud/"))
    end

    it "renders the Organization JSON-LD on every public page" do
      get "/"
      expect(response.body).to include('"@type":"Organization"')
      expect(response.body).to include('"name":"Wokku Cloud"')
    end

    it "does NOT render the Product JSON-LD outside /pricing" do
      get "/"
      expect(response.body).not_to include('"@type":"Product"')
    end

    it "renders hreflang alternates for en + id + x-default" do
      get "/"
      expect(response.body).to include('hreflang="en"')
      expect(response.body).to include('hreflang="id"')
      expect(response.body).to include('hreflang="x-default"')
    end

    it "does NOT render the noindex meta on the public landing" do
      get "/"
      expect(response.body).not_to include('name="robots" content="noindex')
    end
  end

  describe "GET /pricing" do
    it "renders the Product JSON-LD with 4 Offer entries (one per plan)" do
      get "/pricing"
      expect(response.body).to include('"@type":"Product"')
      expect(response.body).to include('"@type":"Offer"')
      # Confirm all 4 plan names appear as offer names
      %w[Free Solo Pro Team].each do |name|
        expect(response.body).to include(%("name":"#{name}"))
      end
      # Confirm USD price string format ("5.00", "15.00", etc.)
      expect(response.body).to include('"price":"5.00"')
      expect(response.body).to include('"price":"15.00"')
      expect(response.body).to include('"price":"50.00"')
      expect(response.body).to include('"priceCurrency":"USD"')
    end

    it "still renders the Organization schema alongside Product" do
      get "/pricing"
      expect(response.body).to include('"@type":"Organization"')
    end
  end

  describe "uses the new self-hosted font preloads (Task 4 + 14 alignment)" do
    it "preloads inter-tight-700 + jetbrains-mono-400 from /fonts/" do
      get "/"
      expect(response.body).to include('<link rel="preload" href="/fonts/inter-tight-700.woff2"')
      expect(response.body).to include('<link rel="preload" href="/fonts/jetbrains-mono-400.woff2"')
    end

    it "no longer references fonts.googleapis.com on public pages" do
      get "/"
      expect(response.body).not_to include("fonts.googleapis.com")
      expect(response.body).not_to include("fonts.gstatic.com")
    end
  end
end
