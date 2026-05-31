require "rails_helper"

RSpec.describe AutoProvisionSharedAddonsJob do
  let(:user)   { create(:user) }
  let(:server) { create(:server) }
  let(:app)    { create(:app_record, creator: user, server: server) }

  it "returns :missing_app when the app id has been deleted" do
    expect(described_class.new.perform(-1)).to eq(:missing_app)
  end

  it "returns :no_engines_selected when enabled_shared_engines is empty" do
    expect(described_class.new.perform(app.id)).to eq(:no_engines_selected)
  end

  it "provisions exactly the engines on enabled_shared_engines" do
    app.update!(enabled_shared_engines: %w[postgres redis])
    provisioner = instance_double(Addons::SharedProvisioner)

    expect(Addons::SharedProvisioner).to receive(:new).with(app: app, engine: "postgres").and_return(provisioner)
    expect(Addons::SharedProvisioner).to receive(:new).with(app: app, engine: "redis").and_return(provisioner)
    expect(provisioner).to receive(:call).twice.and_return(:feature_disabled)

    described_class.new.perform(app.id)
  end

  it "ignores unknown engine names (defensive — user input could be wrong)" do
    # bypass model validation to simulate a stale or corrupt row
    app.update_column(:enabled_shared_engines, %w[postgres riak])
    provisioner = instance_double(Addons::SharedProvisioner)

    expect(Addons::SharedProvisioner).to receive(:new).with(app: app, engine: "postgres").and_return(provisioner)
    expect(Addons::SharedProvisioner).not_to receive(:new).with(app: app, engine: "riak")
    expect(provisioner).to receive(:call).and_return(:feature_disabled)

    described_class.new.perform(app.id)
  end

  it "swallows errors so deploy isn't blocked by addon trouble" do
    app.update!(enabled_shared_engines: %w[postgres])
    allow(Addons::SharedProvisioner).to receive(:new).and_raise(StandardError, "boom")
    expect { described_class.new.perform(app.id) }.not_to raise_error
  end
end
