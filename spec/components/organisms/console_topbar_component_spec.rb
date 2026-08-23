# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::ConsoleTopbarComponent, type: :component do
  it "renders a mobile-only bar with hamburger and logo, zero args" do
    render_inline(described_class.new)
    expect(page).to have_css("div.lg\\:hidden")
    expect(page).to have_css("[data-action='click->mobile-nav#toggle']")
    expect(page).to have_css("a[href='/']")
  end
end
