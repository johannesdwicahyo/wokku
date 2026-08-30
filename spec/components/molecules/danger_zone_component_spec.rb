# frozen_string_literal: true

require "rails_helper"

RSpec.describe Molecules::DangerZoneComponent, type: :component do
  it "renders the title and yielded action content" do
    render_inline(described_class.new(title: "Danger zone")) { "<button>delete</button>".html_safe }

    expect(page).to have_css("h2", text: "Danger zone")
    expect(page).to have_css("h2.text-danger.font-headline.font-bold")
    expect(page).to have_button("delete")
    expect(page).to have_css("div.border-danger.bg-danger-soft")
  end

  it "renders an optional body paragraph" do
    render_inline(described_class.new(title: "Danger zone", body: "This cannot be undone.")) { "action" }

    expect(page).to have_css("p.text-sm.text-ink-soft", text: "This cannot be undone.")
  end

  it "omits the body paragraph when not given" do
    render_inline(described_class.new(title: "Danger zone")) { "action" }

    expect(page).not_to have_css("p.text-sm.text-ink-soft")
  end

  it "never renders a heading prefix like # or //" do
    render_inline(described_class.new(title: "Danger zone", body: "Irreversible.")) { "action" }

    expect(page).not_to have_text("#")
    expect(page).not_to have_text("//")
  end
end
