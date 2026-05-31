require "rails_helper"

RSpec.describe "Per-spike OG images (Phase 1 task 19)", type: :request do
  SPIKE_SLUGS = %w[zero-ops ai-native flat-price one-click-apps].freeze

  describe "static image serving" do
    SPIKE_SLUGS.each do |slug|
      it "[#{slug}] serves all 3 variants (PNG, WebP, AVIF) with 200" do
        %w[png webp avif].each do |ext|
          get "/og/vbs-#{slug}.#{ext}"
          expect(response).to have_http_status(:ok), "GET /og/vbs-#{slug}.#{ext} returned #{response.status}"
        end
      end

      it "[#{slug}] PNG is the canonical OG fallback (size sanity check)" do
        get "/og/vbs-#{slug}.png"
        # PNGs landed around 79–84 KB in dev — assert > 30 KB to catch
        # a stub/empty placeholder regression but not too strict.
        expect(response.body.bytesize).to be > 30_000
      end

      it "[#{slug}] AVIF is the smallest variant (modern consumers prefer it)" do
        avif_bytes = (get "/og/vbs-#{slug}.avif"; response.body.bytesize)
        png_bytes  = (get "/og/vbs-#{slug}.png";  response.body.bytesize)
        expect(avif_bytes).to be < png_bytes
      end
    end
  end

  describe "per-spike LP pages reference their OG image" do
    {
      "zero-ops"       => "vbs-zero-ops.png",
      "ai-native"      => "vbs-ai-native.png",
      "flat-price"     => "vbs-flat-price.png",
      "one-click-apps" => "vbs-one-click-apps.png"
    }.each do |slug, filename|
      it "[/lp/#{slug}] og:image meta points at /og/#{filename}" do
        get "/lp/#{slug}", headers: { "Host" => "wokku.cloud" }
        expect(response.body).to include(%(og:image" content="http://wokku.cloud/og/#{filename}"))
      end
    end
  end
end
