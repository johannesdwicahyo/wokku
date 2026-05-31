# frozen_string_literal: true

require "rails_helper"

RSpec.describe HealthCheckJob, type: :job do
  let(:server) { servers(:one) }

  it "sets server status to connected when client connects" do
    allow_any_instance_of(Dokku::Client).to receive(:connected?).and_return(true)
    described_class.perform_now(server.id)
    expect(server.reload.status).to eq("connected")
  end

  it "sets server status to unreachable when client cannot connect" do
    allow_any_instance_of(Dokku::Client).to receive(:connected?).and_return(false)
    described_class.perform_now(server.id)
    expect(server.reload.status).to eq("unreachable")
  end

  it "sets server status to unreachable on connection error" do
    allow_any_instance_of(Dokku::Client).to receive(:connected?).and_raise(Dokku::Client::ConnectionError, "connection refused")
    described_class.perform_now(server.id)
    expect(server.reload.status).to eq("unreachable")
  end
end
