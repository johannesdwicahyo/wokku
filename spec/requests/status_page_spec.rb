require "rails_helper"

RSpec.describe "Status page", type: :request do
  describe "GET /status (anonymous)" do
    before { get "/status" }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end

    # --- Content intact ---

    it "shows the Dashboard component" do
      expect(response.body).to include("Dashboard")
    end

    it "shows the Database component" do
      expect(response.body).to include("Database")
    end

    it "shows the Background workers component" do
      expect(response.body).to include("Background workers")
    end

    it "shows the Recent incidents section" do
      expect(response.body).to include("recent incidents")
    end

    it "shows the overall status label" do
      expect(response.body).to match(/All systems operational|Degraded performance|Major outage/)
    end

    it "shows a WIB timestamp" do
      expect(response.body).to include("WIB")
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

    it "uses a status dot component (bg-success or bg-danger)" do
      expect(response.body).to match(/bg-success|bg-danger|bg-warn/)
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
end
