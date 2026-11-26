require "rails_helper"

RSpec.describe Organisms::AppLiveLogComponent, type: :component do
  let(:app) { create(:app_record, name: "shop") }

  it "renders All, a button per process, and a named Pause" do
    render_inline(described_class.new(app: app, process_types: %w[web worker]))
    expect(page.all("[role=toolbar] button").map(&:text)).to eq(["All", "web", "worker", "Pause live log"])
    expect(page).to have_css("button[aria-pressed]", count: 3)
    pause = page.find("[data-live-log-target=pauseLabel]").find(:xpath, "..")
    expect(pause.text).to eq("Pause live log")
    expect(pause).not_to have_css("[aria-label]", visible: :all)
    expect(pause["aria-label"]).to be_nil
    expect(pause["aria-pressed"]).to be_nil
    expect(page).to have_css("[role=log][aria-live=off] turbo-frame#app_live_log[src*='lines=50'][loading=lazy]")
  end

  it "localizes to id" do
    I18n.with_locale(:id) { render_inline(described_class.new(app: app, process_types: %w[web])) }
    expect(page).to have_text("Log langsung")
    expect(page).to have_css("button", text: "Jeda log langsung")
  end
end
