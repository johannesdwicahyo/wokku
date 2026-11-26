require "rails_helper"

RSpec.describe Organisms::AppLiveLogComponent, type: :component do
  let(:app) { create(:app_record, name: "shop") }

  it "renders All, a button per process, and a named Pause" do
    render_inline(described_class.new(app: app, process_types: %w[web worker]))
    expect(page.all("[role=toolbar] button").map(&:text)).to eq(%w[All web worker Pause])
    expect(page).to have_css("button[aria-pressed]", count: 4)
    expect(page).to have_css("button[aria-label='Pause live log']", text: "Pause")
    expect(page).to have_css("[role=log][aria-live=off] turbo-frame#app_live_log[src*='lines=50'][loading=lazy]")
  end

  it "localizes to id" do
    I18n.with_locale(:id) { render_inline(described_class.new(app: app, process_types: %w[web])) }
    expect(page).to have_text("Log langsung")
    expect(page).to have_css("button[aria-label='Jeda log langsung']", text: "Jeda")
  end
end
