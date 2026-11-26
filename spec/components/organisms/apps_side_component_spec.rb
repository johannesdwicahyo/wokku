# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::AppsSideComponent, type: :component do
  let(:server) { create(:server) }

  def db(**attrs) = create(:database_service, server: server, **attrs)

  it "renders the panel title with count, a New link and a status light per add-on, no meter without sizes" do
    render_inline(described_class.new(databases: [ db(name: "main-pg") ], total: 1))
    expect(page).to have_text("Databases · 1")
    expect(page).to have_link("New", href: "/dashboard/addons")
    expect(page).to have_text("main-pg")
    expect(page).to have_text("Postgres")
    expect(page).to have_css("[role=img], .wk-light")
    expect(page).not_to have_css("[role=meter]")
  end

  it "shows a usage meter only when used and allocated sizes exist" do
    d = db(name: "sized", live_db_bytes: 512.megabytes, storage_mb_quota: 1024)
    render_inline(described_class.new(databases: [ d, db(name: "plain") ], total: 2))
    expect(page).to have_css("[role=meter]", count: 1)
    expect(page).to have_css("[role=meter][aria-valuenow='5']")
  end

  it "renders an empty state with a New link" do
    render_inline(described_class.new(databases: [], total: 0))
    expect(page).to have_text("No databases yet")
    expect(page).to have_link("New", href: "/dashboard/addons")
  end

  it "caps at 5 and links to all add-ons" do
    dbs = Array.new(7) { |i| db(name: "d#{i}") }
    render_inline(described_class.new(databases: dbs, total: 7))
    expect(page).to have_text("Databases · 7")
    expect(page).to have_css("[data-addon]", count: 5)
    expect(page).to have_link("All add-ons", href: "/dashboard/addons")
  end

  it "localizes under :id" do
    I18n.with_locale(:id) do
      render_inline(described_class.new(databases: [], total: 0))
      expect(page).to have_text("Database · 0")
      expect(page).to have_text("Belum ada database")
      expect(page).to have_link("Baru")
    end
  end

  describe ".sections_for" do
    after { Wokku.config.apps_index_side_sections = nil }

    it "defaults to none" do
      expect(described_class.sections_for(nil, nil)).to eq([])
    end

    it "filters malformed entries" do
      Wokku.config.apps_index_side_sections = ->(_v, _t) { [ { partial: "a/b", locals: { x: 1 } }, "x", { locals: {} } ] }
      expect(described_class.sections_for(nil, nil)).to eq([ { partial: "a/b", locals: { x: 1 } } ])
    end

    it "returns [] and logs when the seam raises" do
      Wokku.config.apps_index_side_sections = ->(_v, _t) { raise "boom" }
      expect(Rails.logger).to receive(:error).with(/boom/)
      expect(described_class.sections_for(nil, nil)).to eq([])
    end
  end
end
