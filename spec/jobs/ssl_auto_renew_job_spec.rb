# frozen_string_literal: true

require "rails_helper"

RSpec.describe SslAutoRenewJob, type: :job do
  it "can be enqueued" do
    expect { described_class.perform_later }.to have_enqueued_job(described_class)
  end

  it "calls letsencrypt:auto-renew for each connected server" do
    servers(:one).update!(status: :connected)

    commands_run = []
    allow_any_instance_of(Dokku::Client).to receive(:run) { |_, cmd| commands_run << cmd }

    described_class.perform_now

    expect(commands_run).to include("letsencrypt:auto-renew")
  end

  it "skips non-connected servers" do
    Server.update_all(status: :unreachable)

    commands_run = []
    allow_any_instance_of(Dokku::Client).to receive(:run) { |_, cmd| commands_run << cmd }

    described_class.perform_now

    expect(commands_run).to be_empty
  end

  it "continues for other servers when one raises an error" do
    servers(:one).update!(status: :connected)
    servers(:two).update!(status: :connected)

    call_count = 0
    allow_any_instance_of(Dokku::Client).to receive(:run) do |_, _cmd|
      call_count += 1
      raise "SSL renew failed" if call_count == 1
    end

    expect { described_class.perform_now }.not_to raise_error
    expect(call_count).to eq(2)
  end
end
