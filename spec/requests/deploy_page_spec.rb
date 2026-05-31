require "rails_helper"

RSpec.describe "Deploy page", type: :request do
  describe "GET /deploy (anonymous)" do
    before { get "/deploy" }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end

    # --- Copy intact ---

    it "shows the page heading" do
      expect(response.body).to include("Deploy Wokku")
    end

    it "shows the Wokku Cloud option" do
      expect(response.body).to include("Wokku Cloud")
    end

    it "shows the RECOMMENDED badge" do
      expect(response.body).to include("RECOMMENDED")
    end

    it "shows PostgreSQL + Redis feature" do
      expect(response.body).to include("PostgreSQL + Redis included")
    end

    it "shows SSL + custom domain feature" do
      expect(response.body).to include("SSL + custom domain")
    end

    it "shows 50+ app templates feature" do
      expect(response.body).to include("50+ app templates")
    end

    it "shows the Deploy Now CTA link" do
      expect(response.body).to include("Deploy Now")
    end

    it "shows the self-host section" do
      expect(response.body).to include("self-host")
    end

    it "shows Hetzner VPS provider" do
      expect(response.body).to include("Hetzner")
    end

    it "shows Vultr VPS provider" do
      expect(response.body).to include("Vultr")
    end

    it "shows DigitalOcean VPS provider" do
      expect(response.body).to include("DigitalOcean")
    end

    it "shows Linode VPS provider" do
      expect(response.body).to include("Linode")
    end

    it "shows the FAQ section" do
      expect(response.body).to include("faq")
    end

    it "shows the self-hosting FAQ question" do
      expect(response.body).to include("difference between Wokku Cloud and self-hosting")
    end

    it "shows the 10% open-source question" do
      expect(response.body).to include("Where does the 10% go")
    end

    it "shows the 10% description copy" do
      expect(response.body).to include("10% supports Wokku + open-source development")
    end

    it "shows the pricing helpers (format_price called)" do
      # Price renders in IDR (Rp) or USD ($) depending on LaunchMode
      expect(response.body).to match(/Rp|\$/)
    end

    # --- Brutalist markers present ---

    it "uses brutalist border-1.5 utility" do
      expect(response.body).to include("border-1.5")
    end

    it "uses brutalist shadow-brutal" do
      expect(response.body).to include("shadow-brutal")
    end

    it "uses brutalist font-mono" do
      expect(response.body).to include("font-mono")
    end

    it "uses brutalist bg-paper" do
      expect(response.body).to include("bg-paper")
    end

    it "uses brutalist text-ink" do
      expect(response.body).to include("text-ink")
    end

    it "uses brutalist bg-bg wrapper" do
      expect(response.body).to include("bg-bg")
    end

    it "uses brutalist text-dim for muted copy" do
      expect(response.body).to include("text-dim")
    end

    it "uses brutalist border-rule-soft dividers" do
      expect(response.body).to include("border-rule-soft")
    end

    it "has details accordion elements for FAQ" do
      expect(response.body).to include("<details")
    end

    it "has summary elements for FAQ accordion" do
      expect(response.body).to include("<summary")
    end

    # --- Hardcoded hex / old tokens absent ---

    it "has no hardcoded hex color values" do
      # &#9660; is a decimal entity (not hex) — exclude it from this check
      body_without_entities = response.body.gsub(/&amp;#\d+;|&#\d+;/, "")
      expect(body_without_entities).not_to match(/#[0-9A-Fa-f]{6}\b|#[0-9A-Fa-f]{3}\b/)
    end

    it "has no text-white utility" do
      expect(response.body).not_to include("text-white")
    end

    it "has no arbitrary bracket color classes (bg-[#...))" do
      expect(response.body).not_to match(/bg-\[#/)
    end

    it "has no arbitrary bracket color classes (text-[#...))" do
      expect(response.body).not_to match(/text-\[#/)
    end

    it "has no arbitrary bracket color classes (border-[#...))" do
      expect(response.body).not_to match(/border-\[#/)
    end

    # --- Material tokens absent ---

    it "has no on-surface Material token" do
      expect(response.body).not_to match(/\bon-surface\b/)
    end

    it "has no bg-surface Material token" do
      expect(response.body).not_to match(/\bbg-surface\b/)
    end

    it "has no outline-variant Material token" do
      expect(response.body).not_to match(/\boutline-variant\b/)
    end

    it "has no surface-container Material token" do
      expect(response.body).not_to match(/\bsurface-container\b/)
    end

    it "has no text-primary Material token" do
      expect(response.body).not_to match(/\btext-primary\b/)
    end

    it "has no material-symbols-outlined icon font" do
      expect(response.body).not_to include("material-symbols-outlined")
    end

    it "has no technical-gradient old class" do
      expect(response.body).not_to include("technical-gradient")
    end
  end
end
