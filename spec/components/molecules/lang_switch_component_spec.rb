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
end
