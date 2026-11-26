require "rails_helper"

RSpec.describe Apps::Fleet do
  def app_with(status, **procs)
    app = create(:app_record, status: status)
    procs.each { |type, n| create(:dyno_allocation, app_record: app, process_type: type.to_s, count: n) }
    app
  end

  def load(*apps) = AppRecord.where(id: apps.map(&:id)).includes(dyno_allocations: :dyno_tier).to_a

  it "gives one running state per process instance" do
    fleet = described_class.for(load(app_with(:running, web: 2, worker: 1)))
    expect(fleet.first[:states]).to eq(%i[running running running])
  end

  it "maps the app status and defaults to one light without allocations" do
    a = app_with(:deploying)
    fleet = described_class.for(load(a))
    expect(fleet).to eq([ { app_id: a.id, name: a.name, states: [ :deploying ] } ])
  end

  it "counts states across apps" do
    fleet = described_class.for(load(app_with(:running, web: 2), app_with(:crashed)))
    expect(described_class.counts(fleet)).to eq(running: 2, crashed: 1)
  end

  it "runs no SQL on preloaded apps" do
    apps = load(app_with(:running, web: 1), app_with(:sleeping, web: 2))
    queries = []
    cb = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(cb, "sql.active_record") { described_class.for(apps) }
    expect(queries).to be_empty
  end
end
