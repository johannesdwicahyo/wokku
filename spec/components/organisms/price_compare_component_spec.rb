require "rails_helper"

RSpec.describe Organisms::PriceCompareComponent, type: :component do
  describe "default (en)" do
    it "anchors against the 3 paid-PaaS competitors" do
      render_inline(described_class.new)
      expect(page).to have_text("Heroku Eco + addons")
      expect(page).to have_text("Vercel Pro")
      expect(page).to have_text("Railway Hobby")
    end

    it "highlights Wokku Solo at $5 flat" do
      render_inline(described_class.new)
      expect(page).to have_text("Wokku Solo")
      expect(page).to have_text(/\$5/)
      expect(page).to have_text(/← that's you/)
    end

    it "uses the refreshed headline + body" do
      render_inline(described_class.new)
      expect(page).to have_text("Same stack. $5 flat.")
      expect(page).to have_text("No metering. No overage.")
    end

    it "drops the old Render entry from the featured row" do
      render_inline(described_class.new)
      # vercel replaces render — Render shouldn't appear in this 4-card grid anymore
      expect(page).not_to have_text("Render Standard")
    end
  end

  describe "id locale" do
    around { |ex| I18n.with_locale(:id) { ex.run } }

    it "shows Rp 75K flat for Wokku and refreshed competitor numbers" do
      render_inline(described_class.new)
      expect(page).to have_text("Rp 75K")
      expect(page).to have_text("Vercel Pro")
      expect(page).to have_text("Stack sama. Rp 75K flat.")
    end
  end
end
