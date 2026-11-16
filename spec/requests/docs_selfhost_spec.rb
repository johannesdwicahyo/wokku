require "rails_helper"

# Docs are served on self-host too: billing pages describe wokku.cloud's
# plans/invoices and must not show there; pages that mix how-to with prices
# say the prices are wokku.cloud's (2026-11-16 audit).
RSpec.describe "Docs on a self-host install", type: :request do
  %w[billing/pricing billing/invoices].each do |path|
    it "404s #{path} and hides the empty Billing section" do
      get "/docs/#{path}"
      expect(response).to have_http_status(:not_found)
      get "/docs/getting-started/first-deploy"
      expect(response.body).not_to include('href="/docs/billing/pricing', 'href="/docs/billing/invoices')
      get "/docs/search-index.json"
      expect(response.parsed_body.pluck("path")).not_to include(path)
    end
  end

  it "says the open-source edition uses dedicated databases" do
    get "/docs/databases/engines"
    expect(response.body).to include("data-dedicated-only-note")
  end

  it "hides the wokku.cloud beta notice" do
    get "/docs/beta"
    expect(response).to have_http_status(:not_found)
  end

  it "explains how sign-up and deploy differ on a self-hosted install" do
    get "/docs/getting-started/first-deploy"
    expect(response.body).to include("data-cloud-flow-note")
  end

  %w[en id].each do |lang|
    it "marks wokku.cloud prices on mixed pages (#{lang})" do
      get "/docs/scaling/resources", params: { lang: lang }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-cloud-prices-note')
    end
  end

  context "on wokku.cloud" do
    before { allow(Wokku).to receive(:cloud?).and_return(true) }

    it "serves the billing pages without the self-host note" do
      get "/docs/billing/pricing"
      expect(response).to have_http_status(:ok)
      get "/docs/scaling/resources"
      expect(response.body).not_to include('data-cloud-prices-note')
    end
  end
end
