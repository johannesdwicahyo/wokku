require "rails_helper"

RSpec.describe "Open Graph meta", type: :request do
  describe "GET / (landing)" do
    it "uses the new 1200x630 default OG image" do
      get "/", headers: { "Host" => "wokku.cloud" }
      expect(response.body).to include(%(<meta property="og:image" content="http://wokku.cloud/og/default.png">))
      expect(response.body).to include(%(<meta property="og:image:width" content="1200">))
      expect(response.body).to include(%(<meta property="og:image:height" content="630">))
    end

    it "includes og:image:alt for accessibility + ranking" do
      get "/"
      expect(response.body).to include('property="og:image:alt"')
      expect(response.body).to include("Stop babysitting servers")
    end

    it "no longer references the old /icon.png as the default OG image" do
      get "/"
      # /icon.png should not appear as the og:image content (it stays as a favicon)
      expect(response.body).not_to match(%r{<meta property="og:image" content="[^"]*/icon\.png"})
    end

    it "uses twitter:card summary_large_image and points at the new image" do
      get "/", headers: { "Host" => "wokku.cloud" }
      expect(response.body).to include('name="twitter:card" content="summary_large_image"')
      expect(response.body).to include(%(<meta name="twitter:image" content="http://wokku.cloud/og/default.png">))
    end
  end

  describe "static OG image files" do
    it "serves the PNG variant via /og/default.png" do
      get "/og/default.png"
      expect(response).to have_http_status(:ok)
      expect(response.body.bytesize).to be > 10_000  # ~57 KB
    end

    it "serves the WebP variant via /og/default.webp" do
      get "/og/default.webp"
      expect(response).to have_http_status(:ok)
      expect(response.body.bytesize).to be > 5_000   # ~25 KB
    end

    it "serves the AVIF variant via /og/default.avif" do
      get "/og/default.avif"
      expect(response).to have_http_status(:ok)
      expect(response.body.bytesize).to be > 3_000   # ~16 KB
    end
  end
end
