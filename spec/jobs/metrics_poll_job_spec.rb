# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetricsPollJob, type: :job do
  let(:server) { servers(:one) }

  def stub_ssh(exec_output, ncpu: 1, mem_total_kb: 2_097_152)
    # NOTE: do NOT use Net::SSH.class_eval + define_singleton_method for
    # stubbing — it bypasses RSpec's per-example teardown and leaks into
    # other specs (clean_ghost_containers, reconcile_app_statuses,
    # docker_health_check all broke from this pattern). `allow(...).to
    # receive(...)` is auto-restored after each example.
    #
    # Command-aware: returns ncpu for `nproc`, a /proc/meminfo dump for the
    # meminfo probe (mem_total_kb: nil simulates an unreadable file →
    # empty output), and exec_output for everything else (docker stats).
    # Default ncpu=1 makes existing assertions on server.live_cpu_pct
    # unchanged (divide by 1 is a no-op).
    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:exec!) do |cmd|
      c = cmd.to_s.strip
      if c == "nproc"
        "#{ncpu}\n"
      elsif c.include?("meminfo")
        mem_total_kb ? "MemTotal:       #{mem_total_kb} kB\nMemFree:         1000000 kB\n" : ""
      else
        exec_output
      end
    end
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
    # may follow (Hosts::Ssh's docker-exec psql for DB sizes, also root) — we
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

  it "SSHes as the configured host SSH user" do
    allow(Wokku.config).to receive(:host_ssh_user).and_return("wokku")
    users = []
    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:exec!) { |_cmd| "" }
    allow(Net::SSH).to receive(:start) { |_h, user, **_o, &block| users << user; block.call(mock_ssh) }

    described_class.perform_now(server.id)
    expect(users.first).to eq("wokku")
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

  describe "wokkud Swarm container names (wokku-<app>-<proc>.<slot>.<task>)" do
    def stats_line(name, cpu, mem)
      { "Name" => name, "CPUPerc" => "#{cpu}%", "MemUsage" => "#{mem}MiB / 512MiB",
        "MemPerc" => "1%", "NetIO" => "0B / 0B", "BlockIO" => "0B / 0B", "PIDs" => "1" }.to_json
    end

    it "attributes each process to its app, preferring the longest matching app name" do
      app = app_records(:one)
      longer = AppRecord.create!(name: "#{app.name}-api", server: server, team: app.team, creator: app.creator)
      stub_ssh([
        stats_line("wokku-#{app.name}-web.1.abc123", "10.00", 100),
        stats_line("wokku-#{app.name}-worker.1.def456", "5.00", 50),
        stats_line("wokku-#{app.name}-api-web.1.ghi789", "2.00", 30),
        stats_line("wokku-run-#{app.name}-0a1b2c3d.1.jkl012", "90.00", 400)
      ].join("\n"))

      described_class.perform_now(server.id)

      expect(app.reload).to have_attributes(live_cpu_pct: 15.0, live_mem_used_mb: 150, live_container_count: 2)
      expect(longer.reload).to have_attributes(live_cpu_pct: 2.0, live_mem_used_mb: 30, live_container_count: 1)
    end
  end

  describe "host capacity from /proc/meminfo" do
    let(:app) { app_records(:one) }

    def stats_line
      {
        "Name" => "#{app.name}.web.1", "CPUPerc" => "5.00%",
        "MemUsage" => "128MiB / 512MiB", "NetIO" => "0B / 0B",
        "BlockIO" => "0B / 0B", "MemPerc" => "25.00%", "PIDs" => "5"
      }.to_json
    end

    it "writes true host RAM to capacity_total_mb and live_mem_total_mb" do
      stub_ssh(stats_line, mem_total_kb: 4_194_304) # 4096 MB
      described_class.perform_now(server.id)
      server.reload
      expect(server.capacity_total_mb).to eq(4096)
      expect(server.live_mem_total_mb).to eq(4096)
    end

    it "sets live_mem_total_mb from host RAM, not the sum of container limits" do
      # Two unlimited containers each report host RAM as their docker limit;
      # the old code summed them (≈ host×N). The denominator must be the
      # true host total instead.
      lines = [
        { "Name" => "#{app.name}.web.1", "CPUPerc" => "1.00%", "MemUsage" => "100MiB / 8000MiB",
          "NetIO" => "0B / 0B", "BlockIO" => "0B / 0B", "MemPerc" => "1.25%", "PIDs" => "1" }.to_json,
        { "Name" => "#{app.name}.worker.1", "CPUPerc" => "1.00%", "MemUsage" => "100MiB / 8000MiB",
          "NetIO" => "0B / 0B", "BlockIO" => "0B / 0B", "MemPerc" => "1.25%", "PIDs" => "1" }.to_json
      ].join("\n")
      stub_ssh(lines, mem_total_kb: 8_192_000) # 8000 MB
      described_class.perform_now(server.id)
      server.reload
      expect(server.live_mem_total_mb).to eq(8000)
      expect(server.live_mem_pct).to be_within(0.1).of(2.5) # 200MB used / 8000MB
    end

    it "leaves capacity_total_mb unchanged when /proc/meminfo can't be read" do
      server.update_columns(capacity_total_mb: 8192)
      stub_ssh(stats_line, mem_total_kb: nil)
      described_class.perform_now(server.id)
      server.reload
      expect(server.capacity_total_mb).to eq(8192)
    end
  end

  describe "dedicated postgres live DB size (W7: docker exec psql via Hosts::Ssh)" do
    let(:svc) { database_services(:one) } # dedicated postgres on servers(:one)

    it "writes live_db_bytes from pg_database_size inside the service container" do
      stub_ssh("")
      captured = nil
      fake_ssh = instance_double(Hosts::Ssh)
      allow(Hosts::Ssh).to receive(:new).and_return(fake_ssh)
      allow(fake_ssh).to receive(:run_raw) do |cmd, stdin:|
        captured = { cmd: cmd, stdin: stdin }
        "pg_database_size\n------------------\n7811072\n(1 row)"
      end

      described_class.perform_now(server.id)

      expect(captured[:cmd]).to eq(
        "docker exec -i dokku.postgres.pg-main psql -U postgres -d pg_main"
      )
      expect(captured[:stdin]).to include("pg_database_size(current_database())")
      expect(svc.reload.live_db_bytes).to eq(7_811_072)
    end

    it "leaves live_db_bytes nil and does not raise when the exec fails" do
      stub_ssh("")
      fake_ssh = instance_double(Hosts::Ssh)
      allow(Hosts::Ssh).to receive(:new).and_return(fake_ssh)
      allow(fake_ssh).to receive(:run_raw).and_raise(Hosts::Ssh::CommandError, "no such container")

      expect { described_class.perform_now(server.id) }.not_to raise_error
      expect(svc.reload.live_db_bytes).to be_nil
    end
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

  # A 20s+ SSH poll routinely gets dropped mid-stream; the host resets the
  # connection (ECONNRESET) or the net-ssh channel closes (IOError). These
  # must be swallowed like the other connection errors — otherwise they
  # become permanent SolidQueue failed executions that wedge the scheduler.
  it "does not raise on ECONNRESET (connection reset mid-poll)" do
    allow(Net::SSH).to receive(:start).and_raise(Errno::ECONNRESET)
    expect { described_class.perform_now(server.id) }.not_to raise_error
  end

  it "does not raise on IOError (closed stream mid-poll)" do
    allow(Net::SSH).to receive(:start).and_raise(IOError, "closed stream")
    expect { described_class.perform_now(server.id) }.not_to raise_error
  end

  describe "server.live_cpu_pct divides by nproc" do
    # docker stats CPUPerc is %-per-core. Summing across containers and
    # NOT dividing by core count produced 40% readings on a 36-core host
    # idling at ~1% real load (founder-spotted 2026-05-31). This block
    # asserts the divisor lands.
    let(:app) { app_records(:one) }

    def cpu_line(cpu_pct)
      {
        "Name" => "#{app.name}.web.1", "CPUPerc" => "#{cpu_pct}%",
        "MemUsage" => "128MiB / 512MiB", "NetIO" => "0B / 0B",
        "BlockIO" => "0B / 0B", "MemPerc" => "25.00%", "PIDs" => "5"
      }.to_json
    end

    it "scales sum down by reported core count" do
      stub_ssh(cpu_line("72.00"), ncpu: 36)
      described_class.perform_now(server.id)
      server.reload
      expect(server.live_cpu_pct).to be_within(0.01).of(2.0)
    end

    it "treats single-core hosts as the no-op case" do
      stub_ssh(cpu_line("33.33"), ncpu: 1)
      described_class.perform_now(server.id)
      server.reload
      expect(server.live_cpu_pct).to be_within(0.01).of(33.33)
    end

    it "falls back to 1 when nproc returns 0 or garbage" do
      stub_ssh(cpu_line("12.50"), ncpu: 0)
      described_class.perform_now(server.id)
      server.reload
      expect(server.live_cpu_pct).to be_within(0.01).of(12.5)
    end

    it "per-app live_cpu_pct stays as the un-divided container sum" do
      # The per-app aggregate is "how many CPU-cores of work is this app
      # doing" and should NOT be divided by host nproc. Only the
      # server-wide rollup gets the divisor.
      stub_ssh(cpu_line("12.50"), ncpu: 36)
      described_class.perform_now(server.id)
      app.reload
      expect(app.live_cpu_pct).to be_within(0.01).of(12.5)
    end
  end
end
