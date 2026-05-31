# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetricsPollJob, type: :job do
  let(:server) { servers(:one) }

  def stub_ssh(exec_output)
    # NOTE: do NOT use Net::SSH.class_eval + define_singleton_method for
    # stubbing — it bypasses RSpec's per-example teardown and leaks into
    # other specs (clean_ghost_containers, reconcile_app_statuses,
    # docker_health_check all broke from this pattern). `allow(...).to
    # receive(...)` is auto-restored after each example.
    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:exec!) { |_cmd| exec_output }
    allow(Net::SSH).to receive(:start) { |*_args, **_opts, &block| block.call(mock_ssh) }
  end

  it "can be enqueued" do
    expect { described_class.perform_later(server.id) }.to have_enqueued_job(described_class)
  end

  it "creates metric records for known apps" do
    app = app_records(:one)
    line = {
      "Name" => "#{app.name}.web.1", "CPUPerc" => "5.20%",
      "MemUsage" => "128MiB / 512MiB", "NetIO" => "1kB / 2kB",
      "BlockIO" => "0B / 0B", "MemPerc" => "25.00%", "PIDs" => "5"
    }.to_json
    stub_ssh(line)

    expect { described_class.perform_now(server.id) }.to change { Metric.count }.by(1)
    metric = Metric.order(:created_at).last
    expect(metric.cpu_percent).to be_within(0.01).of(5.2)
    expect(metric.memory_usage).to eq(128 * 1024 * 1024)
    expect(metric.memory_limit).to eq(512 * 1024 * 1024)
  end

  it "SSHes as root with ssh_private_key from Server record" do
    server.update!(ssh_private_key: "fake-key-data")
    # MetricsPollJob's docker-stats call goes as root. A second Net::SSH.start
    # may follow (Dokku::Client's psql for DB sizes, runs as `dokku`) — we
    # only care about the FIRST call here, so record into an array and
    # assert on calls.first instead of the last captured value.
    calls = []
    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:exec!) { |_cmd| "" }
    allow(Net::SSH).to receive(:start) do |host, user, **opts, &block|
      calls << { host: host, user: user, key_data: opts[:key_data] }
      block.call(mock_ssh)
    end

    described_class.perform_now(server.id)
    expect(calls.first[:user]).to eq("root")
    expect(calls.first[:key_data]).to be_a(Array)
    expect(calls.first[:key_data]).to include("fake-key-data")
  end

  it "logs warning but does not raise on SSH failure" do
    allow(Net::SSH).to receive(:start).and_raise(Net::SSH::Exception, "connection refused")
    expect { described_class.perform_now(server.id) }.not_to raise_error
  end

  it "skips containers not matching known apps" do
    unknown = {
      "Name" => "unknown-container.web.1", "CPUPerc" => "1.00%",
      "MemUsage" => "64MiB / 512MiB", "NetIO" => "0B / 0B",
      "BlockIO" => "0B / 0B", "MemPerc" => "12.50%", "PIDs" => "2"
    }.to_json
    stub_ssh(unknown)
    expect { described_class.perform_now(server.id) }.not_to change { Metric.count }
  end

  it "handles empty docker stats output gracefully" do
    stub_ssh("")
    expect { described_class.perform_now(server.id) }.not_to raise_error
  end

  it "handles JSON parse error gracefully" do
    stub_ssh("not valid json\n")
    expect { described_class.perform_now(server.id) }.not_to raise_error
  end

  it "writes live aggregate columns on the AppRecord" do
    app = app_records(:one)
    line = {
      "Name" => "#{app.name}.web.1", "CPUPerc" => "12.50%",
      "MemUsage" => "200MiB / 512MiB", "MemPerc" => "39.06%",
      "NetIO" => "1kB / 2kB", "BlockIO" => "0B / 0B", "PIDs" => "5"
    }.to_json
    stub_ssh(line)

    described_class.perform_now(server.id)
    app.reload
    expect(app.live_cpu_pct).to be_within(0.01).of(12.5)
    expect(app.live_mem_used_mb).to eq(200)
    expect(app.live_mem_limit_mb).to eq(512)
    expect(app.live_container_count).to eq(1)
    expect(app.live_metrics_at).not_to be_nil
  end

  describe "parse_bytes" do
    let(:job) { described_class.new }

    it "handles GiB unit" do
      expect(job.send(:parse_bytes, "2GiB")).to eq((2 * 1024 * 1024 * 1024).to_i)
    end

    it "handles MiB unit" do
      expect(job.send(:parse_bytes, "128MiB")).to eq((128 * 1024 * 1024).to_i)
    end

    it "handles KiB unit" do
      expect(job.send(:parse_bytes, "256KiB")).to eq((256 * 1024).to_i)
    end

    it "handles raw bytes" do
      expect(job.send(:parse_bytes, "1024")).to eq(1024)
    end
  end

  it "creates multiple metrics for multiple matching containers" do
    app = app_records(:one)
    lines = [
      { "Name" => "#{app.name}.web.1", "CPUPerc" => "1.00%", "MemUsage" => "64MiB / 256MiB",
        "NetIO" => "0B / 0B", "BlockIO" => "0B / 0B", "MemPerc" => "25.00%", "PIDs" => "1" }.to_json,
      { "Name" => "#{app.name}.worker.1", "CPUPerc" => "2.00%", "MemUsage" => "32MiB / 256MiB",
        "NetIO" => "0B / 0B", "BlockIO" => "0B / 0B", "MemPerc" => "12.50%", "PIDs" => "1" }.to_json
    ].join("\n")
    stub_ssh(lines)
    expect { described_class.perform_now(server.id) }.to change { Metric.count }.by(2)
  end

  it "does not raise on ECONNREFUSED" do
    allow(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED)
    expect { described_class.perform_now(server.id) }.not_to raise_error
  end
end
