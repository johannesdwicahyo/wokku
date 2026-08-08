require "rails_helper"

RSpec.describe Atoms::OptimisticButtonComponent, type: :component do
  it "renders a POST button with optimistic-button controller" do
    render_inline(described_class.new(label: "Restart", url: "/restart"))
    expect(page).to have_css('button[data-controller~="motion--optimistic-button"]')
    expect(page).to have_css('[data-motion--optimistic-button-pending-label-value="Restart…"]')
  end
end
