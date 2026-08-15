# frozen_string_literal: true

require "rails_helper"

RSpec.describe SeedKnownHostsJob do
  let(:server) { servers(:one) }

  it "no-ops for a vanished server" do
    expect(Git::KnownHostsWriter).not_to receive(:add)
    described_class.new.perform("00000000-0000-0000-0000-000000000000")
  end

  it "adds the host key and logs success" do
    expect(Git::KnownHostsWriter).to receive(:add).with(server).and_return("host ssh-ed25519 KEY")
    expect(Rails.logger).to receive(:info).with(/added host key for #{server.name}/)
    described_class.new.perform(server.id)
  end

  it "warns when the gateway known_hosts path is unset" do
    allow(Git::KnownHostsWriter).to receive(:add).and_return(nil)
    expect(Rails.logger).to receive(:warn).with(/WOKKU_GATEWAY_KNOWN_HOSTS_PATH not set/)
    described_class.new.perform(server.id)
  end

  it "reports writer errors instead of raising" do
    allow(Git::KnownHostsWriter).to receive(:add)
      .and_raise(Git::KnownHostsWriter::Error, "keyscan failed")
    expect(Rails.logger).to receive(:error).with(/keyscan failed/)
    expect { described_class.new.perform(server.id) }.not_to raise_error
  end
end
