require "rails_helper"

RSpec.describe Organisms::FinalCtaComponent, type: :component do
  describe "default (en)" do
    it "renders the three-spike summary headline" do
      render_inline(described_class.new)
      expect(page).to have_text("Your weekend back. Your bill predictable.")
      expect(page).to have_text("Your AI in the driver's seat.")
    end

    it "renders the refreshed sub-body referencing Free + $5" do
      render_inline(described_class.new)
      expect(page).to have_text("Free forever for hobby projects")
      expect(page).to have_text(/\$5\/mo/)
    end

    it "renders the start_free CTA + docs + WhatsApp" do
      render_inline(described_class.new)
      expect(page).to have_text("> start_free()")
      expect(page).to have_text("> read_docs()")
      expect(page).to have_text("> chat_wa()")
    end

    it "no longer references the freelance-VPS framing" do
      render_inline(described_class.new)
      expect(page).not_to have_text("stop babysitting")
      expect(page).not_to have_text("Push code.")
    end
  end

  describe "id locale" do
    around { |ex| I18n.with_locale(:id) { ex.run } }

    it "renders Indonesian three-spike headline" do
      render_inline(described_class.new)
      expect(page).to have_text("Weekend kamu balik")
      expect(page).to have_text("AI kamu di kursi sopir")
    end
  end
end
