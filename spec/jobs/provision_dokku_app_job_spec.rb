# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProvisionDokkuAppJob, type: :job do
  let(:app) { app_records(:one) }

  it "calls apps:create when the app is not on Dokku yet" do
    expect_any_instance_of(Dokku::Apps).to receive(:list).and_return([ "other-app" ])
    expect_any_instance_of(Dokku::Apps).to receive(:create).with(app.name).once
    described_class.perform_now(app.id)
  end

  it "skips create when the Dokku-side app already exists" do
    expect_any_instance_of(Dokku::Apps).to receive(:list).and_return([ app.name, "other-app" ])
    expect_any_instance_of(Dokku::Apps).not_to receive(:create)
    described_class.perform_now(app.id)
  end

  it "swallows Dokku command errors so the AppRecord stays created" do
    allow_any_instance_of(Dokku::Apps).to receive(:list)
      .and_raise(Dokku::Client::ConnectionError, "boom")
    expect { described_class.perform_now(app.id) }.not_to raise_error
  end

  it "no-op when the AppRecord is gone (race with destroy)" do
    expect_any_instance_of(Dokku::Apps).not_to receive(:list)
    described_class.perform_now("00000000-0000-7000-8000-000000000000")
  end
end
