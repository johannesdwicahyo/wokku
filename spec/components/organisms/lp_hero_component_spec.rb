require "rails_helper"

RSpec.describe Organisms::LpHeroComponent, type: :component do
  describe "constructor" do
    it "accepts each known spike (symbol or string)" do
      Organisms::LpHeroComponent::SPIKES.each do |spike|
        expect { described_class.new(spike: spike) }.not_to raise_error
        expect { described_class.new(spike: spike.to_sym) }.not_to raise_error
      end
    end

    it "raises ArgumentError for an unknown spike" do
      expect { described_class.new(spike: "bogus") }.to raise_error(ArgumentError, /unknown spike/)
    end
  end

  describe "zero_ops variant" do
    it "renders strike-through on 'babysitting' (en)" do
      render_inline(described_class.new(spike: "zero_ops"))
      expect(page).to have_text("Stop")
      expect(page).to have_css("span.line-through", text: "babysitting")
      expect(page).to have_text("servers.")
      expect(page).to have_text(/Wokku handles patching/)
    end

    it "uses the > stop_babysitting() primary CTA" do
      render_inline(described_class.new(spike: "zero_ops"))
      expect(page).to have_text("> stop_babysitting()")
    end
  end

  describe "ai_native variant" do
    it "renders WITHOUT strike-through (no headline_strike key)" do
      render_inline(described_class.new(spike: "ai_native"))
      expect(page).not_to have_css("span.line-through")
      expect(page).to have_text("Your AI")
      expect(page).to have_text("can deploy this for you.")
    end

    it "uses the > let_ai_deploy() primary CTA" do
      render_inline(described_class.new(spike: "ai_native"))
      expect(page).to have_text("> let_ai_deploy()")
    end
  end

  describe "flat_price variant" do
    it "renders strike-through on 'No metering.'" do
      render_inline(described_class.new(spike: "flat_price"))
      expect(page).to have_text("One price.")
      expect(page).to have_css("span.line-through", text: "No metering.")
      expect(page).to have_text("No surprises.")
    end
  end

  describe "one_click_apps variant" do
    it "renders WITHOUT strike-through and includes 'in 60 seconds.'" do
      render_inline(described_class.new(spike: "one_click_apps"))
      expect(page).not_to have_css("span.line-through")
      expect(page).to have_text("Install")
      expect(page).to have_text("Ghost, n8n, WordPress")
      expect(page).to have_text("in 60 seconds.")
    end
  end

  describe "consistency across all 4 spikes" do
    Organisms::LpHeroComponent::SPIKES.each do |spike|
      it "[#{spike}] renders the 5 shared pills + secondary CTA + cta_note" do
        render_inline(described_class.new(spike: spike))
        # 5 pills (shared with main hero)
        expect(page).to have_text("QRIS")
        expect(page).to have_text("From Rp 75K / $5")
        expect(page).to have_text("Jakarta")
        expect(page).to have_text("WhatsApp")
        expect(page).to have_text("AI-native")
        # Secondary CTA (constant across all spikes)
        expect(page).to have_text("> see_pricing()")
        # CTA note (constant)
        expect(page).to have_text("// free tier · no card · live in ~60s")
      end
    end
  end

  describe "id locale" do
    around { |ex| I18n.with_locale(:id) { ex.run } }

    it "[zero_ops] renders Indonesian copy" do
      render_inline(described_class.new(spike: "zero_ops"))
      expect(page).to have_text("Berhenti")
      expect(page).to have_css("span.line-through", text: "ngurusin")
      expect(page).to have_text("server.")
    end

    it "[ai_native] renders Indonesian copy without strike" do
      render_inline(described_class.new(spike: "ai_native"))
      expect(page).not_to have_css("span.line-through")
      expect(page).to have_text("AI kamu")
      expect(page).to have_text("bisa deploy ini.")
    end
  end
end
