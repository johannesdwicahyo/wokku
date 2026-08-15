require "rails_helper"

RSpec.describe Atoms::PillComponent, type: :component do
  it "renders content with the default accent dot" do
    render_inline(described_class.new) { "hello" }
    expect(page).to have_text("hello")
    expect(page).to have_css("span.bg-accent.rounded-full")
  end

  it "renders a custom dot tone and merges extra classes" do
    render_inline(described_class.new(dot: :danger, class: "mt-4")) { "warn" }
    expect(page).to have_css("span.bg-danger")
    expect(page).to have_css("span.mt-4", text: "warn")
  end
end
