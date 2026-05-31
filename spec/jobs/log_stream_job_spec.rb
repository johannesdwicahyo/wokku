# frozen_string_literal: true

require "rails_helper"

RSpec.describe LogStreamJob, type: :job do
  let(:app) { app_records(:one) }

  it "can be enqueued" do
    expect { described_class.perform_later(app.id, "channel-abc") }.to have_enqueued_job(described_class)
  end

  it "streams logs and broadcasts to LogChannel" do
    broadcast_calls = []
    allow_any_instance_of(Dokku::Client).to receive(:run_streaming) do |_, _cmd, &block|
      block.call("log line 1\n")
      block.call("log line 2\n")
    end
    allow(LogChannel).to receive(:broadcast_to) do |_chan, payload|
      broadcast_calls << payload
    end

    described_class.perform_now(app.id, "channel-abc")

    expect(broadcast_calls.size).to eq(2)
    expect(broadcast_calls.first[:type]).to eq("log")
    expect(broadcast_calls.first[:data]).to include("log line 1")
  end

  it "returns early when app not found" do
    expect { described_class.perform_now(0, "channel-abc") }.not_to raise_error
  end

  it "broadcasts error message on ConnectionError" do
    broadcast_calls = []
    allow_any_instance_of(Dokku::Client).to receive(:run_streaming).and_raise(Dokku::Client::ConnectionError, "SSH refused")
    allow(LogChannel).to receive(:broadcast_to) { |_chan, payload| broadcast_calls << payload }

    described_class.perform_now(app.id, "channel-abc")

    expect(broadcast_calls.last[:type]).to eq("error")
    expect(broadcast_calls.last[:data]).to include("SSH refused")
  end
end
