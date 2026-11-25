require "rails_helper"

RSpec.describe Atoms::StatusPillComponent, type: :component do
  describe "status API (existing)" do
    it "renders the outline-dot badge for running" do
      render_inline(described_class.new(status: "running"))
      expect(page).to have_text("Running")
      expect(page).to have_css("span.border-line.rounded-full")
      expect(page).to have_css("span[style*='--color-success']")
    end

    it "falls back to the stopped style for unknown statuses" do
      render_inline(described_class.new(status: "weird"))
      expect(page).to have_text("Stopped")
      expect(page).to have_css("span[style*='--color-dim']")
    end
  end

  describe "label + tone API (new)" do
    it "renders label with success tone" do
      render_inline(described_class.new(label: "Succeeded", tone: :success))
      expect(page).to have_text("Succeeded")
      expect(page).to have_css("span[style*='--color-success']")
    end

    it "renders label with danger tone" do
      render_inline(described_class.new(label: "Failed", tone: :danger))
      expect(page).to have_text("Failed")
      expect(page).to have_css("span[style*='--color-danger']")
    end

    it "renders label with deploying tone" do
      render_inline(described_class.new(label: "Building", tone: :deploying))
      expect(page).to have_text("Building")
      expect(page).to have_css("span[style*='--color-deploying']")
    end

    it "renders label with warn tone" do
      render_inline(described_class.new(label: "Sleeping", tone: :warn))
      expect(page).to have_text("Sleeping")
      expect(page).to have_css("span[style*='--color-warn']")
    end

    it "renders label with info tone" do
      render_inline(described_class.new(label: "Info", tone: :info))
      expect(page).to have_text("Info")
      expect(page).to have_css("span[style*='--color-info']")
    end

    it "defaults tone to neutral when omitted" do
      render_inline(described_class.new(label: "Neutral"))
      expect(page).to have_text("Neutral")
      expect(page).to have_css("span[style*='--color-dim']")
    end
  end
end
