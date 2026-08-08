# frozen_string_literal: true

require "rails_helper"

RSpec.describe Molecules::AddonSummaryCardComponent, type: :component do
  let(:team) { create(:team) }
  let(:server) { create(:server, team: team) }
  let(:db) { DatabaseService.create!(name: "pg-card", service_type: "postgres", server: server) }

  # Regression (2026-06-09): this card renders inside the app detail page's
  # app_tab_content turbo-frame. Its link points to the standalone addon
  # detail page (no app_tab_content), so it MUST break out to the top level
  # or Turbo shows "Content missing".
  it "links to the addon detail page breaking out of the turbo-frame" do
    render_inline(described_class.new(database_service: db))

    link = page.find("a[href='/dashboard/addons/#{db.id}']")
    expect(link["data-turbo-frame"]).to eq("_top")
  end
end
