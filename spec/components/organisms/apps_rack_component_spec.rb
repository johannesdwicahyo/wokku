# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::AppsRackComponent, type: :component do
  let(:team) { create(:team) }
  let(:server) { create(:server, team: team) }
  let(:a) { create(:app_record, team: team, server: server, name: "alpha") }
  let(:b) { create(:app_record, team: team, server: server, name: "bravo") }
  let(:sparks) { { a.id => [ 5, 10, nil ] + Array.new(9, 40), b.id => [] } }

  def render_rack(apps: [ a, b ], last_deploys: {}, crashes: {}, sparks: self.sparks)
    render_inline(described_class.new(apps: apps, sparks: sparks, last_deploys: last_deploys, crashes: crashes))
  end

  it "orders units by last deploy desc, nil last" do
    render_rack(last_deploys: { b.id => 1.hour.ago, a.id => 1.day.ago })
    expect(page.all("a[data-rack-unit]").map { |n| n["data-rack-unit"] }).to eq(%w[bravo alpha])
    render_rack(last_deploys: { b.id => 1.hour.ago })
    expect(page.all("a[data-rack-unit]").map { |n| n["data-rack-unit"] }).to eq(%w[bravo alpha])
  end

  it "renders panel title, sort note, aria-hidden header and unit link with record-panel action" do
    render_rack
    expect(page).to have_text("Apps · 2")
    expect(page).to have_text("Sort · last deploy")
    expect(page).to have_css("[aria-hidden='true']", text: "Domain")
    unit = page.find("a[data-rack-unit='alpha']")
    expect(unit["href"]).to eq("/dashboard/apps/#{a.id}")
    expect(unit["data-action"]).to include("click->record-panel#show")
    expect(unit["data-record-panel-src-param"]).to eq("/dashboard/apps/#{a.id}/panel")
  end

  it "shows a status light, sleeping note, CPU bars and no-data state" do
    b.update_columns(status: AppRecord.statuses[:sleeping])
    render_rack
    expect(page.find("a[data-rack-unit='bravo']")).to have_text("sleeping, wakes on visit")
    expect(page.find("a[data-rack-unit='bravo']")).to have_css("[aria-label='No CPU data yet']")
    expect(page.find("a[data-rack-unit='alpha']")).to have_css("i", count: 12)
  end

  it "shows the crash note and alert with logs link and reason" do
    a.update_columns(status: AppRecord.statuses[:crashed])
    render_rack(crashes: { a.id => { count: 3, reason: "connection refused" } })
    expect(page).to have_text("crashed 3× in 10 min")
    expect(page).to have_text("alpha keeps exiting with \"connection refused\". Wokku is restarting it.")
    expect(page).to have_link("See logs", href: "/dashboard/apps/#{a.id}/logs")
  end

  it "omits the reason when unknown and caps alerts at 3" do
    apps = Array.new(4) { |i| create(:app_record, team: team, server: server, name: "c#{i}", status: :crashed) }
    render_rack(apps: apps, sparks: {}, crashes: apps.to_h { |x| [ x.id, { count: 1, reason: nil } ] })
    expect(page).to have_text("keeps exiting. Wokku is restarting it.", count: 3)
    expect(page).to have_link("See logs", count: 3)
  end

  it "uses the identical grid classes on the header and every row" do
    render_rack
    header = page.find("[aria-hidden='true']", text: "Domain")["class"].split
    row = page.find("a[data-rack-unit='alpha']")["class"].split
    grid = header.select { |c| c.include?("grid-cols") }
    expect(grid).not_to be_empty
    expect(row & grid).to eq(grid)
  end

  it "renders a New app unit without a doubled plus" do
    render_rack
    link = page.find("a[href='/dashboard/apps/new']")
    expect(link.text.scan("+").size).to be <= 1
    expect(link.text).to include("New app")
  end

  it "localises under :id" do
    I18n.with_locale(:id) { render_rack }
    expect(page).to have_text("App · 2")
    expect(page).to have_text("Urut · deploy terakhir")
  end

  describe ".crashes_for" do
    it "groups recent crashes per app in one query with the last log line as reason" do
      create_crash = ->(app, at, log) { CrashEvent.create!(app_record: app, container_id: SecureRandom.hex(4), exited_at: at, log_excerpt: log) }
      create_crash.(a, 2.minutes.ago, "x\nold reason")
      create_crash.(a, 1.minute.ago, "boom\nnew reason\n")
      create_crash.(a, 1.hour.ago, "stale")
      result = described_class.crashes_for([ a, b ])
      expect(result).to eq(a.id => { count: 2, reason: "new reason" })
    end
  end

  describe "crash reason extraction" do
    def reason_for(log)
      CrashEvent.create!(app_record: a, container_id: SecureRandom.hex(4), exited_at: 1.minute.ago, log_excerpt: log)
      described_class.crashes_for([ a ])[a.id][:reason]
    end

    it "prefers the error line of a Node stack trace and strips ANSI" do
      log = "\e[31mnode:internal/modules\e[0m\n\n\e[1mError: Cannot find module 'express'\e[0m\n    at Module._resolveFilename (x.js:1)\n    at Function.load (y.js:2)\nNode.js v20"
      expect(reason_for(log)).to eq("Error: Cannot find module 'express'")
    end

    it "falls back to the last line" do
      expect(reason_for("one\ntwo\n")).to eq("two")
    end
  end

  it "renders a script-tag reason escaped" do
    a.update_columns(status: AppRecord.statuses[:crashed])
    render_rack(crashes: { a.id => { count: 1, reason: "<script>alert(1)</script>" } })
    expect(page.native.to_html).not_to include("<script>alert")
    expect(page).to have_text("<script>alert(1)</script>")
  end

  describe ".last_deploys_for" do
    it "returns the latest succeeded finish per app" do
      create(:deploy, app_record: a, status: :succeeded, finished_at: 2.hours.ago)
      create(:deploy, app_record: a, status: :failed, finished_at: 1.minute.ago)
      expect(described_class.last_deploys_for([ a, b ])[a.id]).to be_within(1.second).of(2.hours.ago)
      expect(described_class.last_deploys_for([ a, b ])).not_to have_key(b.id)
    end
  end
end
