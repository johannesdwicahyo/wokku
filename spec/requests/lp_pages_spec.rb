require "rails_helper"

RSpec.describe "Pages::LpController", type: :request do
  before do
    %w[free solo pro team].each do |k|
      Plan.find_or_create_by!(key: k) { |p| p.name = k.capitalize }
    end
  end

  describe "GET /lp/:spike — all 4 valid spikes" do
    %w[zero-ops ai-native flat-price one-click-apps].each do |slug|
      it "[#{slug}] renders successfully" do
        get "/lp/#{slug}"
        expect(response).to have_http_status(:ok)
      end

      it "[#{slug}] emits noindex meta" do
        get "/lp/#{slug}"
        expect(response.body).to include('<meta name="robots" content="noindex,nofollow">')
      end

      it "[#{slug}] points og:image at the per-spike OG file", headers: { "Host" => "wokku.cloud" } do
        get "/lp/#{slug}", headers: { "Host" => "wokku.cloud" }
        expect(response.body).to include(%(og:image" content="http://wokku.cloud/og/vbs-#{slug}.png"))
      end

      it "[#{slug}] tags landing_variant when analytics is enabled" do
        allow_any_instance_of(ApplicationController).to receive(:analytics_enabled?).and_return(true)
        ENV["POSTHOG_API_KEY"] = "test_key"
        get "/lp/#{slug}"
        expect(response.body).to include("vbs-#{slug}-v1")
      ensure
        ENV.delete("POSTHOG_API_KEY")
      end
    end
  end

  describe "spike → component variant mapping" do
    {
      "zero-ops"       => { headline_marker: "babysitting",         cta: "stop_babysitting" },
      "ai-native"      => { headline_marker: "Your AI",             cta: "let_ai_deploy" },
      "flat-price"     => { headline_marker: "One price",           cta: "see_flat_pricing" },
      "one-click-apps" => { headline_marker: "Ghost, n8n, WordPress", cta: "install_first_app" }
    }.each do |slug, expected|
      it "[#{slug}] renders the right LpHero variant" do
        get "/lp/#{slug}"
        expect(response.body).to include(expected[:headline_marker])
        # `>` in CTA copy gets HTML-escaped to `&gt;` in the response.body
        # text-match — assert on the command name only, which is stable.
        expect(response.body).to include("#{expected[:cta]}()")
      end
    end
  end

  describe "GET /lp/<unknown>" do
    it "returns 404 (routing constraint rejects)" do
      get "/lp/bogus-spike"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "main landing default landing_variant" do
    it "/ tags vps-but-simpler-v1 (not a /lp/* override)" do
      allow_any_instance_of(ApplicationController).to receive(:analytics_enabled?).and_return(true)
      ENV["POSTHOG_API_KEY"] = "test_key"
      get "/"
      expect(response.body).to include("vps-but-simpler-v1")
    ensure
      ENV.delete("POSTHOG_API_KEY")
    end
  end
end
