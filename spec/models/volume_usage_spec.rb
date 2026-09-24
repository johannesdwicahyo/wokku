require "rails_helper"

RSpec.describe "volume usage readers" do
  let(:server) { create(:server) }

  it "sums an app's volumes from the heartbeat" do
    app = create(:app_record, server: server, name: "shop")
    allow(app).to receive(:mounts_for_converge).and_return([ { "volume" => "wokku-shop-uploads", "path" => "/app/uploads" } ])
    server.update!(vitals: { "volume_usage" => { "/var/lib/docker/volumes/wokku-shop-uploads/_data" => 3 * 1024**3 } })
    expect(app.volume_used_gb).to eq(3.0)
  end

  it "reads a datastore's data dir" do
    db = create(:database_service, server: server, service_type: "postgres", name: "shopdb")
    server.update!(vitals: { "volume_usage" => { "/var/lib/dokku/services/postgres/shopdb/data" => 512 * 1024**2 } })
    expect(db.disk_used_gb).to eq(0.5)
  end

  it "returns nil without telemetry" do
    expect(create(:database_service, server: server).disk_used_gb).to be_nil
  end
end
