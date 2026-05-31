require "rails_helper"

RSpec.describe Organisms::EmptyStateComponent, type: :component do
  it "renders headline + body" do
    render_inline(described_class.new(headline: "No templates", body: "Pick from the gallery"))
    expect(page).to have_text("No templates")
    expect(page).to have_text("Pick from the gallery")
  end

  it "renders primary + secondary CTAs when provided" do
    render_inline(described_class.new(
      headline: "Nothing yet", body: "Add one",
      cta_label: "Add", cta_href: "/new",
      secondary_label: "Learn more", secondary_href: "/docs"
    ))
    expect(page).to have_link("Add", href: "/new")
    expect(page).to have_link("Learn more", href: "/docs")
  end

  it "renders without CTA block when no labels given" do
    render_inline(described_class.new(headline: "Empty", body: "Nothing here"))
    expect(page).not_to have_css("a")
  end
end
