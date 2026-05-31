require "rails_helper"

MATERIAL_TOKENS = %w[
  on-surface
  bg-surface
  outline-variant
  text-primary
  bg-primary
  text-secondary
  bg-secondary
  text-error
  bg-error
  surface-container
  text-outline
].freeze

BRUTALIST_MARKERS = %w[border-1.5 font-mono bg-paper text-ink border-rule-soft].freeze

RSpec.describe "Legal pages", type: :request do
  # ---------------------------------------------------------------------------
  # /terms (EN)
  # ---------------------------------------------------------------------------
  describe "GET /terms (anonymous, EN locale)" do
    before { get "/terms" }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end

    # --- Representative legal copy intact ---
    it "shows the introductory clause" do
      expect(response.body).to include("By using Wokku")
    end

    it "shows section 3 acceptable use heading" do
      expect(response.body).to include("Acceptable Use")
    end

    it "shows section 4 enforcement heading" do
      expect(response.body).to include("Enforcement")
    end

    it "shows the contact email" do
      expect(response.body).to include("legal@wokku.cloud")
    end

    it "shows the locale switcher to Bahasa Indonesia" do
      expect(response.body).to include("Bahasa Indonesia")
    end

    # --- Brutalist markers present ---
    BRUTALIST_MARKERS.each do |marker|
      it "uses brutalist #{marker} utility" do
        expect(response.body).to include(marker)
      end
    end

    # --- Material tokens absent ---
    MATERIAL_TOKENS.each do |token|
      it "has no #{token} Material token" do
        expect(response.body).not_to include(token)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # /terms (ID)
  # ---------------------------------------------------------------------------
  describe "GET /terms (ID locale via Accept-Language)" do
    before { get "/terms", headers: { "Accept-Language" => "id" } }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # /privacy (EN)
  # ---------------------------------------------------------------------------
  describe "GET /privacy (anonymous, EN locale)" do
    before { get "/privacy" }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end

    # --- Representative legal copy intact ---
    it "shows the introductory clause" do
      expect(response.body).to include("This Privacy Policy describes how Wokku")
    end

    it "shows section 2 Claude Code plugin heading" do
      expect(response.body).to include("Claude Code Plugin Data Handling")
    end

    it "shows section 4 third-party services heading" do
      expect(response.body).to include("Third-Party Services")
    end

    it "shows iPaymu as a third-party service" do
      expect(response.body).to include("iPaymu")
    end

    it "shows the privacy contact email" do
      expect(response.body).to include("privacy@wokku.cloud")
    end

    it "shows the locale switcher to Bahasa Indonesia" do
      expect(response.body).to include("Bahasa Indonesia")
    end

    # --- Brutalist markers present ---
    BRUTALIST_MARKERS.each do |marker|
      it "uses brutalist #{marker} utility" do
        expect(response.body).to include(marker)
      end
    end

    # --- Material tokens absent ---
    MATERIAL_TOKENS.each do |token|
      it "has no #{token} Material token" do
        expect(response.body).not_to include(token)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # /privacy (ID)
  # ---------------------------------------------------------------------------
  describe "GET /privacy (ID locale via Accept-Language)" do
    before { get "/privacy", headers: { "Accept-Language" => "id" } }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # /refund (EN)
  # ---------------------------------------------------------------------------
  describe "GET /refund (anonymous, EN locale)" do
    before { get "/refund" }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end

    # --- Representative legal copy intact ---
    it "shows the introductory clause" do
      expect(response.body).to include("This Refund Policy explains when and how")
    end

    it "shows the 14-day window section" do
      expect(response.body).to include("14-Day Refund Window")
    end

    it "shows the non-refundable charges section" do
      expect(response.body).to include("Non-Refundable Charges")
    end

    it "shows the PT Wokku company contact block" do
      expect(response.body).to include("PT Wokku")
    end

    it "shows Sukawati address" do
      expect(response.body).to include("Sukawati")
    end

    it "shows the WhatsApp number" do
      expect(response.body).to include("+62 851 2194 8822")
    end

    it "shows the locale switcher to Bahasa Indonesia" do
      expect(response.body).to include("Bahasa Indonesia")
    end

    # --- Brutalist markers present ---
    BRUTALIST_MARKERS.each do |marker|
      it "uses brutalist #{marker} utility" do
        expect(response.body).to include(marker)
      end
    end

    # --- Material tokens absent ---
    MATERIAL_TOKENS.each do |token|
      it "has no #{token} Material token" do
        expect(response.body).not_to include(token)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # /refund (ID)
  # ---------------------------------------------------------------------------
  describe "GET /refund (ID locale via Accept-Language)" do
    before { get "/refund", headers: { "Accept-Language" => "id" } }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end
  end
end
