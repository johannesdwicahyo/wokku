require "rails_helper"

RSpec.describe Atoms::StatusLightComponent, type: :component do
  def sq = page.find("span[role='img'], span.wk-light", match: :first)

  {
    running:   %w[bg-live wk-glow-live],
    healthy:   %w[bg-live wk-glow-live],
    deploying: %w[bg-ink wk-blink-1s],
    crashed:   %w[bg-danger wk-glow-bad wk-blink-14s],
    sleeping:  %w[wk-outline-muted],
    stopped:   %w[wk-outline-muted],
    created:   %w[bg-dark-line]
  }.each do |state, classes|
    it "renders #{state} with #{classes.join(' ')}" do
      render_inline(described_class.new(state: state))
      classes.each { |c| expect(page).to have_css("span.#{c}") }
    end
  end

  it "labels the square for assistive tech when no visible label" do
    render_inline(described_class.new(state: :running))
    expect(page).to have_css("span[role='img'][aria-label='Running']")
    render_inline(described_class.new(state: :crashed))
    expect(page).to have_css("span[role='img'][aria-label='Crashed']")
  end

  it "shows the visible label when given" do
    render_inline(described_class.new(state: :running, label: "Live now"))
    expect(page).to have_text("Live now")
    expect(page).not_to have_css("[role='img']")
  end

  it "uses the size" do
    render_inline(described_class.new(state: :running, size: 14))
    expect(page).to have_css("span[style*='width:14px']")
  end

  it "decorative hides the light from assistive tech" do
    render_inline(described_class.new(state: :running, decorative: true))
    expect(page).to have_css("span.wk-light[aria-hidden='true']")
    expect(page).not_to have_css("[role='img'], [aria-label]")
  end
end
