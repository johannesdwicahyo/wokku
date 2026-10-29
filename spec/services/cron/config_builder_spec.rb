require "rails_helper"

RSpec.describe Cron::ConfigBuilder do
  let(:server) { create(:server) }
  let(:app)    { create(:app_record, server: server, name: "myapp") }
  let!(:deploy) { create(:deploy, :succeeded, :wokkud, app_record: app) }

  it "emits entries for enabled tasks on this server only" do
    task = create(:scheduled_task, app_record: app, schedule: "*/5 * * * *", command: "bin/rails cleanup", enabled: true)
    create(:scheduled_task, app_record: app, enabled: false)
    other = create(:app_record, server: create(:server))
    create(:scheduled_task, app_record: other, enabled: true)

    json = described_class.new(server).as_json
    expect(json["entries"].length).to eq(1)
    e = json["entries"].first
    expect(e).to eq(
      "id" => task.id, "app" => "myapp", "schedule" => "*/5 * * * *",
      "command" => "exec /bin/bash -l -c bin/rails\\ cleanup", "timeout_seconds" => 900,
      "image_ref" => deploy.wokkud_image_ref, "networks" => [ "wokku-services" ]
    )
  end

  it "runs the command as-is for non-wokkud images and skips apps with nothing deployed" do
    deploy.update!(builder: "dokku")
    app.lifecycle_ops.create!(server: server, kind: "stack.converge", status: "succeeded", params: { "image_ref" => "registry/wokku/myapp:adopt-1" })
    create(:scheduled_task, app_record: app, command: "echo hi", enabled: true)
    never = create(:app_record, server: server, name: "never-deployed")
    create(:scheduled_task, app_record: never, enabled: true)

    entries = described_class.new(server).as_json["entries"]
    expect(entries.map { |e| [ e["app"], e["image_ref"], e["command"] ] })
      .to eq([ [ "myapp", "registry/wokku/myapp:adopt-1", "echo hi" ] ])
  end

  it "includes the app's shared-engine networks" do
    parent = create(:database_service, server: server, name: "dokku-shared-postgres",
                    service_type: "postgres", tier_name: "shared_host", shared: false, status: :running)
    tenant = create(:database_service, server: server, service_type: "postgres",
                    shared: true, parent_service: parent, status: :running)
    create(:app_database, app_record: app, database_service: tenant)
    create(:scheduled_task, app_record: app, enabled: true)

    e = described_class.new(server).as_json["entries"].first
    expect(e["networks"]).to eq([ "dokku-shared-postgres", "wokku-services" ])
  end

  it "has a stable version that changes only with content" do
    create(:scheduled_task, app_record: app, enabled: true)
    v1 = described_class.new(server).version
    expect(described_class.new(server).version).to eq(v1)
    create(:scheduled_task, app_record: app, enabled: true, command: "other")
    expect(described_class.new(server).version).not_to eq(v1)
  end
end
