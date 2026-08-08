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

  it "re-raises provisioning errors so retry_on can drive a retry (no silent swallow)" do
    app.update!(enabled_shared_engines: %w[postgres])
    allow(Addons::SharedProvisioner).to receive(:new).and_raise(StandardError, "boom")
    expect { described_class.new.perform(app.id) }.to raise_error(StandardError, "boom")
  end

  it "is configured to retry transient failures" do
    handlers = described_class.rescue_handlers.map(&:first)
    expect(handlers).to include("StandardError")
  end

  it "still discards deleted-record / deserialization errors (discard_on wins over the StandardError catch-all)" do
    handlers = described_class.rescue_handlers.map(&:first)
    std_idx = handlers.index("StandardError")
    expect(std_idx).not_to be_nil
    # ActiveJob matches most-recently-registered first; these discards must be
    # registered AFTER (later index than) the StandardError retry to win.
    expect(handlers.rindex("ActiveRecord::RecordNotFound")).to be > std_idx
    expect(handlers.rindex("ActiveJob::DeserializationError")).to be > std_idx
  end
end
