require "rails_helper"

RSpec.describe "FAQ page", type: :request do
  describe "GET /faq (anonymous, EN locale)" do
    before { get "/faq" }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end

    # --- Content intact ---

    it "shows the Getting Started section" do
      expect(response.body).to include("What is Wokku?")
    end

    it "shows the Billing section" do
      expect(response.body).to include("How does billing work?")
    end

    it "shows the Deployment section" do
      expect(response.body).to include("How do I deploy my app?")
    end

    it "shows the Data &amp; Security section" do
      expect(response.body).to include("Where is my data stored?")
    end

    it "shows the Support section" do
      expect(response.body).to include("How do I contact support?")
    end

    it "shows the locale switcher to Bahasa Indonesia" do
      expect(response.body).to include("Bahasa Indonesia")
    end

    # --- Brutalist markers present ---

    it "uses brutalist border-1.5 utility" do
      expect(response.body).to include("border-1.5")
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

    it "uses brutalist border-rule-soft dividers" do
      expect(response.body).to include("border-rule-soft")
    end

    it "has details accordion elements" do
      expect(response.body).to include("<details")
    end

    it "has summary elements for accordion" do
      expect(response.body).to include("<summary")
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

    it "has no text-outline Material token" do
      expect(response.body).not_to match(/\btext-outline\b/)
    end

    it "has no text-primary Material token" do
      expect(response.body).not_to match(/\btext-primary\b/)
    end

    it "has no material-symbols-outlined icon font" do
      expect(response.body).not_to include("material-symbols-outlined")
    end
  end

  describe "GET /faq (anonymous, ID locale)" do
    before { get "/faq", headers: { "Accept-Language" => "id" } }

    # The ID view is served when the session locale is :id.
    # Without switching via the form, GET /faq returns EN by default.
    # We just confirm the route resolves cleanly to 200.
    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end
  end
end
