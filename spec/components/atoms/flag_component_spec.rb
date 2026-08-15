require "rails_helper"

RSpec.describe Atoms::FlagComponent, type: :component do
  it "renders the sm size by default" do
    render_inline(described_class.new)
    expect(page).to have_css("span[aria-label='Indonesia']")
    expect(page).to have_css("span.bg-hot[style*='width: 22px'][style*='height: 7px']")
  end

  it "renders other sizes" do
    render_inline(described_class.new(size: :lg))
    expect(page).to have_css("span.bg-paper[style*='width: 36px'][style*='height: 12px']")
  end
end
