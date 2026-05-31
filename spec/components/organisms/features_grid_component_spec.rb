require "rails_helper"

RSpec.describe Organisms::FeaturesGridComponent, type: :component do
  describe "default (en)" do
    it "renders all 6 features with the new copy" do
      render_inline(described_class.new)
      [
        "Push to deploy",
        "1-click templates",
        "PR Previews",
        "Scheduled tasks",
        "Transfer app",
        "AI-native"
      ].each do |title|
        expect(page).to have_text(title)
      end
    end

    it "no longer renders deprecated tiles (11 add-ons, browser console, free SSL + domains, CLI · API · MCP)" do
      render_inline(described_class.new)
      expect(page).not_to have_text("11 managed add-ons")
      expect(page).not_to have_text("Browser console")
      expect(page).not_to have_text("Free SSL + domains")
      expect(page).not_to have_text("CLI · API · MCP")
    end

    it "renders the refreshed eyebrow + headline" do
      render_inline(described_class.new)
      expect(page).to have_text("// the boring stuff, done right")
      expect(page).to have_text("Production-grade, built in.")
    end
  end

  describe "id locale" do
    around { |ex| I18n.with_locale(:id) { ex.run } }

    it "renders the Indonesian feature copy" do
      render_inline(described_class.new)
      expect(page).to have_text("Deploy lewat git push")
      expect(page).to have_text("Template 1-klik")
      expect(page).to have_text("PR Previews")
      expect(page).to have_text("Scheduled tasks")
      expect(page).to have_text("Transfer app")
      expect(page).to have_text("AI-native")
    end
  end
end
