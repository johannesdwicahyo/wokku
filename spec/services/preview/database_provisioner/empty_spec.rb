require "rails_helper"

RSpec.describe Preview::DatabaseProvisioner::Empty do
  let(:server) { create(:server) }
  let(:parent) { create(:app_record, name: "myapp", server: server) }
  let(:preview) { create(:app_record, :preview, parent_app: parent, pr_number: 7, team: parent.team, server: server) }
  let(:client) { instance_double(Dokku::Client) }
  let(:databases) { instance_double(Dokku::Databases) }

  before do
    allow(Dokku::Client).to receive(:new).with(server).and_return(client)
    allow(Dokku::Databases).to receive(:new).with(client).and_return(databases)
  end

  it "creates and links a fresh DB for each parent service" do
    db = create(:database_service, service_type: "postgres", name: "myapp-db", server: server)
    create(:app_database, app_record: parent, database_service: db, alias_name: db.service_type.upcase)

    expect(databases).to receive(:create).with("postgres", "myapp-pr-7-db")
    expect(databases).to receive(:link).with("postgres", "myapp-pr-7-db", "myapp-pr-7")

    described_class.new(preview).provision
  end

  it "no-ops when parent has no databases" do
    expect(databases).not_to receive(:create)
    expect(databases).not_to receive(:link)
    expect { described_class.new(preview).provision }.not_to raise_error
  end

  it "uses parent name prefix to derive preview DB name" do
    # If parent DB is `myapp-cache`, preview should get `myapp-pr-7-cache`.
    db = create(:database_service, service_type: "redis", name: "myapp-cache", server: server)
    create(:app_database, app_record: parent, database_service: db, alias_name: db.service_type.upcase)

    expect(databases).to receive(:create).with("redis", "myapp-pr-7-cache")
    expect(databases).to receive(:link).with("redis", "myapp-pr-7-cache", "myapp-pr-7")

    described_class.new(preview).provision
  end
end
