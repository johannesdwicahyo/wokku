# frozen_string_literal: true

require "rails_helper"

# These specs lock in the queue split that prevents SSH-heavy probe
# jobs from starving billing on a single shared worker pool — the
# regression that caused the May 2026 daily-debit outage.
RSpec.describe "Queue isolation", type: :job do
  it "routes billing jobs to the :billing queue" do
    # DailyDebitJob / DailyDebitSchedulerJob / BalanceCheckJob deleted in 1.8.
    expect(BillingSanityCheckJob.queue_name).to eq("billing")
    expect(Billing::IssueUpcomingInvoicesJob.queue_name).to eq("billing")
    expect(Billing::SuspendOverdueJob.queue_name).to eq("billing")
  end

  it "routes SSH-heavy probe jobs to :health" do
    expect(HealthCheckJob.queue_name).to eq("health")
    expect(DnsVerificationJob.queue_name).to eq("health")
  end

  it "routes server-sync jobs to :sync" do
    expect(SyncServerJob.queue_name).to eq("sync")
  end

  it "keeps metrics polling on :metrics" do
    expect(MetricsPollJob.queue_name).to eq("metrics")
  end

  # Regression guard for 2026-05-16: when queues were split for isolation,
  # `deploys` and `notifications` were left without explicit worker pools,
  # silently piling up DeployJob + NotifyJob for ~2 days until the
  # brightbean-studio deploy surfaced it. Every queue_as used in the
  # codebase MUST appear in at least one queue.yml worker pool.
  it "every queue_as value has at least one worker pool covering it" do
    declared = Dir[Rails.root.join("app/jobs/**/*.rb")].flat_map do |f|
      File.read(f).scan(/^\s*queue_as\s+:(\w+)/).flatten
    end.uniq

    cfg = YAML.safe_load(ERB.new(File.read(Rails.root.join("config/queue.yml"))).result, aliases: true)
    pools = cfg.fetch("default").fetch("workers").flat_map { |w| Array(w["queues"]) }

    declared.each do |q|
      expect(pools).to include(q),
        "queue `#{q}` is referenced via queue_as but no worker pool in queue.yml processes it"
    end
  end

  it "queue.yml runs billing on its own worker pool" do
    cfg = YAML.safe_load(ERB.new(File.read(Rails.root.join("config/queue.yml"))).result, aliases: true)
    workers = cfg.fetch("default").fetch("workers")
    billing_pool = workers.find { |w| w["queues"] == "billing" || Array(w["queues"]).include?("billing") }
    expect(billing_pool).not_to be_nil, "expected a worker entry dedicated to the :billing queue"
    expect(Array(billing_pool["queues"])).to eq([ "billing" ]),
      "the :billing queue should not share a worker pool with anything else"
  end
end
