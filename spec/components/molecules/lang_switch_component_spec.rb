require "rails_helper"

RSpec.describe Molecules::LangSwitchComponent, type: :component do
  it "marks the current locale active and the other inactive" do
    render_inline(described_class.new(current: "en"))
    expect(page).to have_button("EN")
    expect(page).to have_button("ID")
    expect(page.find_button("EN")[:class]).to include("bg-ink text-bg")
    expect(page.find_button("ID")[:class]).to include("text-ink-soft")
  end

  it "activates :id when current is id" do
    render_inline(described_class.new(current: :id))
    expect(page.find_button("ID")[:class]).to include("bg-ink text-bg")
    expect(page.find_button("EN")[:class]).to include("text-ink-soft")
  end

  it "gives each button a full accessible name, lang on ID, and aria-current on the current one" do
    render_inline(described_class.new(current: "en"))
    expect(page).to have_css("button[aria-label='English'][aria-current='true']")
    expect(page).to have_css("button[aria-label='Bahasa Indonesia'][lang='id']")
    expect(page).not_to have_css("button[aria-label='Bahasa Indonesia'][aria-current]")
  end

  it "does not clip focus outlines and keeps 24px hit targets" do
    render_inline(described_class.new(current: "en"))
    expect(page).not_to have_css(".overflow-hidden")
    expect(page).to have_css("button.min-h-6", count: 2)
  end
end
