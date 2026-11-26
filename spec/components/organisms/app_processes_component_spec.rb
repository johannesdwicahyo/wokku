# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::AppProcessesComponent, type: :component do
  let(:team) { create(:team) }
  let(:server) { create(:server, team: team) }
  let(:app) { create(:app_record, team: team, server: server) }

  def alloc(type, count)
    DynoAllocation.create!(app_record: app, process_type: type, count: count, cpu: 0.5, memory_mb: 512)
  end

  def render_it(can_update: true)
    render_inline(described_class.new(app: app.reload, can_update: can_update))
  end

  before do
    alloc("worker", 1)
    alloc("web", 2)
    app.update!(live_containers: [ { "process" => "web", "state" => "running" }, { "process" => "web", "state" => "running" },
                                   { "process" => "worker", "state" => "failed" } ])
  end

  it "orders web first and counts running tasks" do
    render_it
    expect(page.all("[data-process]").map { |n| n["data-process"] }).to eq(%w[web worker])
    expect(page.find("[data-process='web']")).to have_text("2 running")
    expect(page.find("[data-process='worker']")).to have_text("0 running")
    expect(page).to have_text("Size · 0.5 vCPU · 512 MB each")
  end

  it "disables minus at zero and posts return_to overview" do
    app.process_scales.create!(process_type: "worker", count: 0)
    render_it
    expect(page.find("[data-process='worker'] button[aria-label='Remove one worker process']")).to be_disabled
    form = page.find("[data-process='web'] button[aria-label='Add one web process']").find(:xpath, "ancestor::form")
    expect(form["action"]).to eq("/dashboard/apps/#{app.id}/scaling")
    expect(form).to have_css("input[name='scaling[web]'][value='3']", visible: :all)
    expect(form).to have_css("input[name='return_to'][value='overview']", visible: :all)
  end

  it "renders no buttons for a viewer" do
    render_it(can_update: false)
    expect(page).to have_no_css("button")
  end

  it "mentions Rp in the confirm only when pricing returns a number" do
    render_it
    expect(page.find("button[aria-label='Add one web process']")["data-turbo-confirm"]).to eq("Add one web process?")
    allow(Wokku.config.pricing).to receive(:monthly_idr).and_return(60_000)
    render_it
    expect(page.find("button[aria-label='Add one web process']")["data-turbo-confirm"]).to eq("Add one web process? +Rp60.000/month")
  end

  it "localizes under :id" do
    allow(Wokku.config.pricing).to receive(:monthly_idr).and_return(60_000)
    I18n.with_locale(:id) { render_it }
    expect(page).to have_text("0 berjalan")
    expect(page).to have_css("button[aria-label='Tambah satu proses web']")
    expect(page.find("button[aria-label='Tambah satu proses web']")["data-turbo-confirm"]).to eq("Tambah satu proses web? +Rp60.000/bulan")
  end
end
