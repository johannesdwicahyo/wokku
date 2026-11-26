require "rails_helper"

RSpec.describe Addons::AttachOnCreate do
  let(:user)   { create(:user) }
  let(:team)   { create(:team, owner: user) }
  let(:server) { create(:server) }
  let(:app)    { create(:app_record, team: team, creator: user, server: server) }
  let(:small)  { Resources::Shape::DB_SHORTCUTS["small"] }

  before do
    create(:team_membership, team: team, user: user) unless team.team_memberships.exists?(user: user)
    allow(CreateAddonJob).to receive(:perform_later)
  end

  def run(*items) = described_class.call(app: app, user: user, items: items)

  it "attaches shared postgres" do
    sp = instance_double(Addons::SharedProvisioner, call: :provisioned)
    allow(Addons::SharedProvisioner).to receive(:new).with(app: app, engine: "postgres").and_return(sp)
    r = run({ kind: "shared", engine: "postgres" })
    expect(r.attached).to eq([ "postgres" ])
    expect(r.failed).to be_empty
  end

  it "creates, links and enqueues a dedicated postgres" do
    allow(Wokku.config).to receive(:resource_builder?).and_return(true)
    allow(Resources::ApplyChange).to receive(:check_new_shape).and_return(double(ok: true))
    r = run({ kind: "dedicated", engine: "postgres", shape: small })
    expect(r.failed).to be_empty
    db = DatabaseService.find_by!(name: r.attached.first)
    expect([ db.cpu.to_f, db.memory_mb, db.disk_gb ]).to eq([ 0.25, 256, 1 ])
    expect(app.app_databases.where(database_service: db)).to exist
    expect(CreateAddonJob).to have_received(:perform_later).with(db.id, app.id)
  end

  it "fails a dedicated item with an invalid shape and still attaches the rest" do
    allow(Wokku.config).to receive(:resource_builder?).and_return(true)
    db = create(:database_service, server: server, creator: user, status: :running)
    r = run({ kind: "dedicated", engine: "postgres", shape: { cpu: 99, memory_mb: 1, disk_gb: 1 } },
            { kind: "existing", database_service_id: db.id })
    expect(r.failed.size).to eq(1)
    expect(r.attached).to eq([ db.name ])
  end

  it "links an existing add-on on the same server" do
    db = create(:database_service, server: server, creator: user, status: :running)
    r = run({ kind: "existing", database_service_id: db.id })
    expect(r.attached).to eq([ db.name ])
    expect(app.app_databases.where(database_service: db)).to exist
  end

  it "fails an existing add-on the user cannot see" do
    db = create(:database_service, server: server, creator: create(:user))
    r = run({ kind: "existing", database_service_id: db.id })
    expect(r.failed.first[:error]).to eq("Add-on not available")
    expect(app.app_databases.where(database_service: db)).not_to exist
  end

  it "fails an existing add-on on another server" do
    db = create(:database_service, server: create(:server), creator: user)
    r = run({ kind: "existing", database_service_id: db.id })
    expect(r.failed.size).to eq(1)
    expect(app.app_databases.where(database_service: db)).not_to exist
  end

  it "ignores items past the 5th" do
    allow(Addons::SharedProvisioner).to receive(:new).and_return(instance_double(Addons::SharedProvisioner, call: :provisioned))
    r = run(*Array.new(6) { { kind: "shared", engine: "redis" } })
    expect(r.outcomes.size).to eq(5)
  end

  it "sets the DSN env when linking an existing add-on" do
    db = create(:database_service, server: server, creator: user, status: :running)
    db.update!(dsn: "postgres://u:p@h/db")
    allow(Apps::Restarter).to receive(:restart)
    expect(Apps::EnvWriter).to receive(:set).with(app, hash_including("POSTGRES_URL"))
    run({ kind: "existing", database_service_id: db.id })
  end

  it "refuses existing shared tenants and not-running databases" do
    shared = create(:database_service, server: server, creator: user, status: :running)
    shared.update_column(:shared, true)
    stopped = create(:database_service, server: server, creator: user, status: :stopped)
    r = run({ kind: "existing", database_service_id: shared.id }, { kind: "existing", database_service_id: stopped.id })
    expect(r.failed.size).to eq(2)
    expect(app.app_databases.count).to eq(0)
  end

  it "refuses an existing database that belongs to another team" do
    other_app = create(:app_record, server: server)
    db = create(:database_service, server: server, creator: user, status: :running)
    other_app.app_databases.create!(database_service: db, alias_name: "POSTGRES")
    r = run({ kind: "existing", database_service_id: db.id })
    expect(r.failed.size).to eq(1)
    expect(app.app_databases.count).to eq(0)
  end

  it "fails only the item whose provisioner raises" do
    db = create(:database_service, server: server, creator: user, status: :running)
    allow(Addons::SharedProvisioner).to receive(:new).and_raise("boom secret")
    r = run({ kind: "shared", engine: "postgres" }, { kind: "existing", database_service_id: db.id })
    expect(r.failed.map { |f| f[:error] }).to eq([ "Couldn't attach add-on" ])
    expect(r.attached).to eq([ db.name ])
  end

  it "fails every kind for a viewer" do
    viewer = create(:user)
    create(:team_membership, team: team, user: viewer, role: :viewer)
    db = create(:database_service, server: server, creator: viewer, status: :running)
    allow(Wokku.config).to receive(:resource_builder?).and_return(true)
    r = described_class.call(app: app, user: viewer, items: [
      { kind: "shared", engine: "postgres" }, { kind: "dedicated", engine: "postgres", shape: small },
      { kind: "existing", database_service_id: db.id } ])
    expect(r.failed.size).to eq(3)
    expect(r.failed.map { |f| f[:error] }.uniq).to eq([ "Not authorized" ])
    expect(DatabaseService.where(server: server).count).to eq(1)
    expect(app.app_databases.count).to eq(0)
  end

  describe ".existing_candidates" do
    it "returns exactly what attach accepts: dedicated, running, same server, team-owned" do
      ok = create(:database_service, server: server, creator: user, status: :running)
      create(:database_service, server: create(:server), creator: user, status: :running)
      create(:database_service, server: server, creator: user, status: :stopped)
      shared = create(:database_service, server: server, creator: user, status: :running)
      shared.update_column(:shared, true)
      expect(described_class.existing_candidates(user: user, team: team, server: server)).to eq([ ok ])
      expect(described_class.existing_candidates(user: user, team: team, server: nil)).to eq([])
    end
  end
end
