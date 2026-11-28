require "rails_helper"

RSpec.describe Organisms::DocsTopBarComponent, type: :component do
  # Devise defines user_signed_in? lazily (on first route load), so verify-
  # partial-doubles can't see it in an isolated run.
  def signed_in(value)
    without_partial_double_verification { allow(vc_test_controller).to receive(:user_signed_in?).and_return(value) }
  end

  before { signed_in(false) }

  it "marks the API tab current when active: :api" do
    render_inline(described_class.new(active: :api, locale: :en))
    expect(page).to have_css("nav a[aria-current='page']", text: "API reference")
    expect(page).to have_css("nav a[aria-current='page']", count: 1)
  end

  it "renders brand, search with shortcuts, the EN/ID switch and Sign in" do
    render_inline(described_class.new(active: :guides, locale: :en))
    expect(page).to have_link(href: "/docs", text: "Docs")
    expect(page).to have_css("button[data-action~='docs-search#open'] kbd")
    expect(page).to have_button("EN")
    expect(page).to have_link("Sign in", href: "/users/sign_in")
  end

  it "shows Dashboard when signed in" do
    signed_in(true)
    render_inline(described_class.new(active: :guides, locale: :en))
    expect(page).to have_link("Dashboard", href: "/dashboard")
  end
end
