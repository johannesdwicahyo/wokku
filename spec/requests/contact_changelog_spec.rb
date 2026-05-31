require "rails_helper"

RSpec.describe "Contact and Changelog pages", type: :request do
  describe "GET /contact" do
    before { get "/contact" }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end

    it "contains the WhatsApp link" do
      expect(response.body).to include("https://wa.me/6285121948822")
    end

    it "contains the support email" do
      expect(response.body).to include("support@wokku.cloud")
    end

    it "has brutalist markers (bg-paper, font-mono, text-ink tokens)" do
      b = response.body
      expect(b).to include("bg-paper")
      expect(b).to include("font-mono")
      expect(b).to include("text-ink")
      expect(b).to include("border-1.5")
    end

    it "has no Material Design color tokens" do
      b = response.body
      expect(b).not_to match(/\btext-on-surface\b/)
      expect(b).not_to match(/\bbg-surface\b/)
    end

    it "has no bare hex color values in class attributes" do
      # No inline hex colors like #abc123 in class="" strings
      expect(response.body).not_to match(/class="[^"]*#[0-9a-fA-F]{3,6}/)
    end
  end

  describe "GET /changelog" do
    before { get "/changelog" }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end

    it "contains the seeded entry text" do
      b = response.body
      expect(b).to include("Public beta")
      expect(b).to include("git push")
      expect(b).to include("Rupiah")
    end

    it "has brutalist markers (bg-paper, font-mono, text-ink tokens)" do
      b = response.body
      expect(b).to include("bg-paper")
      expect(b).to include("font-mono")
      expect(b).to include("text-ink")
      expect(b).to include("border-1.5")
    end

    it "has no Material Design color tokens" do
      b = response.body
      expect(b).not_to match(/\btext-on-surface\b/)
      expect(b).not_to match(/\bbg-surface\b/)
    end

    it "has no bare hex color values in class attributes" do
      expect(response.body).not_to match(/class="[^"]*#[0-9a-fA-F]{3,6}/)
    end
  end

  describe "GET /blog" do
    it "returns 404 (route removed)" do
      get "/blog"
      expect(response).to have_http_status(:not_found)
    end
  end
end
