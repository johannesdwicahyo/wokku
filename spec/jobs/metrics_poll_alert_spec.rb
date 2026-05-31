# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MetricsPollJob alerting", type: :job do
  let(:server) { servers(:one) }
  let(:app) { app_records(:one) }

  around do |ex|
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ex.run
    Rails.cache = original
  end

  def run_job_with_stats(cpu_perc:, mem_usage:)
    container_name = "#{app.name}.web.1"
    line = {
      "Name" => container_name, "CPUPerc" => cpu_perc, "MemUsage" => mem_usage,
      "NetIO" => "0B / 0B", "BlockIO" => "0B / 0B", "MemPerc" => "0%", "PIDs" => "1"
    }.to_json

    # Use RSpec's per-example stub teardown — class_eval/define_singleton_method
    # leaks Net::SSH.start into every subsequent spec, breaking unrelated
    # SSH-using job specs (clean_ghost_containers, docker_health_check,
    # reconcile_app_statuses).
    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:exec!) { |_cmd| line }
    allow(Net::SSH).to receive(:start) { |*_args, **_opts, &block| block.call(mock_ssh) }

    MetricsPollJob.perform_now(server.id)
  end

  it "does not fire alert on first high CPU reading" do
    expect { run_job_with_stats(cpu_perc: "85.0%", mem_usage: "128MiB / 512MiB") }
      .not_to have_enqueued_job(NotifyJob)
  end

  it "increments CPU cache counter to 1 on first high reading" do
    run_job_with_stats(cpu_perc: "85.0%", mem_usage: "128MiB / 512MiB")
    expect(Rails.cache.read("alert:#{app.id}:resource_high_cpu")).to eq(1)
  end

  it "resets CPU counter when reading drops below threshold" do
    run_job_with_stats(cpu_perc: "85.0%", mem_usage: "128MiB / 512MiB")
    run_job_with_stats(cpu_perc: "50.0%", mem_usage: "128MiB / 512MiB")
    expect(Rails.cache.read("alert:#{app.id}:resource_high_cpu")).to be_nil
  end

  it "resets CPU counter to 0 after alert fires on second consecutive high reading" do
    run_job_with_stats(cpu_perc: "85.0%", mem_usage: "128MiB / 512MiB")
    run_job_with_stats(cpu_perc: "85.0%", mem_usage: "128MiB / 512MiB")
    expect(Rails.cache.read("alert:#{app.id}:resource_high_cpu")).to eq(0)
  end

  it "does not increment CPU counter when CPU is exactly at threshold" do
    run_job_with_stats(cpu_perc: "80.0%", mem_usage: "128MiB / 512MiB")
    expect(Rails.cache.read("alert:#{app.id}:resource_high_cpu")).to be_nil
  end

  it "does not fire alert on first high memory reading" do
    expect { run_job_with_stats(cpu_perc: "5.0%", mem_usage: "471MiB / 512MiB") }
      .not_to have_enqueued_job(NotifyJob)
  end

  it "increments memory cache counter to 1 on first high reading" do
    run_job_with_stats(cpu_perc: "5.0%", mem_usage: "471MiB / 512MiB")
    expect(Rails.cache.read("alert:#{app.id}:resource_high_memory")).to eq(1)
  end

  it "resets memory counter when usage drops below threshold" do
    run_job_with_stats(cpu_perc: "5.0%", mem_usage: "471MiB / 512MiB")
    run_job_with_stats(cpu_perc: "5.0%", mem_usage: "128MiB / 512MiB")
    expect(Rails.cache.read("alert:#{app.id}:resource_high_memory")).to be_nil
  end

  it "resets memory counter to 0 after alert fires on second consecutive high reading" do
    run_job_with_stats(cpu_perc: "5.0%", mem_usage: "471MiB / 512MiB")
    run_job_with_stats(cpu_perc: "5.0%", mem_usage: "471MiB / 512MiB")
    expect(Rails.cache.read("alert:#{app.id}:resource_high_memory")).to eq(0)
  end

  describe "#check_threshold" do
    let(:job) { MetricsPollJob.new }

    it "increments cache on first breach" do
      job.send(:check_threshold, app, "resource_high_cpu", 85.0, 80.0)
      expect(Rails.cache.read("alert:#{app.id}:resource_high_cpu")).to eq(1)
    end

    it "deletes cache key when value is below threshold" do
      Rails.cache.write("alert:#{app.id}:resource_high_cpu", 1, expires_in: 1.hour)
      job.send(:check_threshold, app, "resource_high_cpu", 50.0, 80.0)
      expect(Rails.cache.read("alert:#{app.id}:resource_high_cpu")).to be_nil
    end

    it "does not trigger at exactly threshold value" do
      job.send(:check_threshold, app, "resource_high_cpu", 80.0, 80.0)
      expect(Rails.cache.read("alert:#{app.id}:resource_high_cpu")).to be_nil
    end

    it "resets counter to 0 after firing alert on second breach" do
      job.send(:check_threshold, app, "resource_high_cpu", 85.0, 80.0)
      job.send(:check_threshold, app, "resource_high_cpu", 85.0, 80.0)
      expect(Rails.cache.read("alert:#{app.id}:resource_high_cpu")).to eq(0)
    end
  end
end
