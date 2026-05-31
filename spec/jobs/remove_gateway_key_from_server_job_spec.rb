# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemoveGatewayKeyFromServerJob, type: :job do
  let(:server) { servers(:one) }

  it "removes the named key via Dokku::SshKeys#remove" do
    expect_any_instance_of(Dokku::SshKeys).to receive(:remove).with("wokku-gateway-old").once
    described_class.perform_now(server.id, "wokku-gateway-old")
  end

  it "short-circuits when the server id is gone" do
    expect_any_instance_of(Dokku::SshKeys).not_to receive(:remove)
    described_class.perform_now("00000000-0000-7000-8000-000000000000", "wokku-gateway-old")
  end

  it "swallows Dokku connection errors (logs + reports to Sentry instead)" do
    allow_any_instance_of(Dokku::SshKeys).to receive(:remove)
      .and_raise(Dokku::Client::ConnectionError, "ssh down")
    expect { described_class.perform_now(server.id, "wokku-gateway-old") }.not_to raise_error
  end
end
