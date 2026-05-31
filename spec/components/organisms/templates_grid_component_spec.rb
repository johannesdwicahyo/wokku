require "rails_helper"

RSpec.describe Organisms::TemplatesGridComponent, type: :component do
  describe "default (en)" do
    it "features all 6 vibecoder/agency picks in row 1" do
      render_inline(described_class.new)
      %w[Ghost n8n WordPress NocoDB Plausible].each do |name|
        expect(page).to have_text(name)
      end
      expect(page).to have_text("Uptime Kuma")
    end

    it "renders the cPanel-familiar headline" do
      render_inline(described_class.new)
      expect(page).to have_text("deployed in 60 seconds")
    end

    it "exposes the new templates as the leading six" do
      lead_six = described_class::TEMPLATES.first(6).map { |t| t[:name] }
      expect(lead_six).to eq(["Ghost", "n8n", "WordPress", "NocoDB", "Plausible", "Uptime Kuma"])
    end

    it "renders a 12-card grid (no template count regression)" do
      expect(described_class::TEMPLATES.size).to eq(12)
    end
  end

  describe "id locale" do
    around { |ex| I18n.with_locale(:id) { ex.run } }

    it "renders the Indonesian headline" do
      render_inline(described_class.new)
      expect(page).to have_text("deploy dalam 60 detik")
    end
  end
end
