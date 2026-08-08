require "rails_helper"

RSpec.describe Cron::RunRecorder do
  let(:server) { create(:server) }
  let(:app)    { create(:app_record, server: server) }
  let(:task)   { create(:scheduled_task, app_record: app) }
  let(:notification) { create(:notification, team: app.team, events: %w[scheduled_task_failing scheduled_task_recovered]) }

  # Distinct started_at per call: scheduled_task_runs now has a unique index
  # on [scheduled_task_id, started_at] (Fix 5 — dedupes retried cron-run
  # reports), and consecutive calls within one example can land in the same
  # iso8601-second, which would collide and silently dedupe as a retry.
  def next_tick
    @tick = (@tick || 0) + 1
    (Time.current + @tick.seconds).iso8601
  end

  def record(exit_code)
    described_class.new(server).call([ { "task_id" => task.id, "started_at" => next_tick,
      "finished_at" => Time.current.iso8601, "exit_code" => exit_code, "log_excerpt" => "boom" } ])
  end

  it "persists rows and drops unknown task ids" do
    n = described_class.new(server).call([
      { "task_id" => task.id, "started_at" => Time.current.iso8601, "exit_code" => 0 },
      { "task_id" => SecureRandom.uuid, "started_at" => Time.current.iso8601, "exit_code" => 0 }
    ])
    expect(n).to eq(1)
    expect(task.runs.count).to eq(1)
  end

  it "drops rows for a task whose app lives on another server" do
    other_server = create(:server)
    other_app = create(:app_record, server: other_server)
    other_task = create(:scheduled_task, app_record: other_app)

    n = described_class.new(server).call([
      { "task_id" => other_task.id, "started_at" => Time.current.iso8601, "exit_code" => 0 }
    ])
    expect(n).to eq(0)
    expect(other_task.runs.count).to eq(0)
  end

  it "fires failing on exactly the 3rd consecutive failure, recovery on next success" do
    notification
    expect { record(1); record(1) }.not_to have_enqueued_job(NotifyJob)
    expect { record(1) }.to have_enqueued_job(NotifyJob) # 3rd
    expect { record(1) }.not_to have_enqueued_job(NotifyJob) # 4th: no re-fire
    expect { record(0) }.to have_enqueued_job(NotifyJob) # recovery
    expect { record(0) }.not_to have_enqueued_job(NotifyJob)
  end

  it "skips a malformed row but still records the rest of the batch" do
    other_task = create(:scheduled_task, app_record: app)
    n = described_class.new(server).call([
      { "task_id" => task.id, "started_at" => next_tick, "exit_code" => 0 },
      { "task_id" => other_task.id, "started_at" => nil, "exit_code" => 0 }, # missing started_at -> NotNullViolation
      { "task_id" => task.id, "started_at" => next_tick, "exit_code" => 0 }
    ])
    expect(n).to eq(2)
    expect(task.runs.count).to eq(2)
    expect(other_task.runs.count).to eq(0)
  end

  it "a duplicated cron-run report (retry after a lost ack) doesn't create a dup row or inflate the streak" do
    notification
    record(1) # failure 1
    record(1) # failure 2
    ts = Time.current.iso8601
    third = { "task_id" => task.id, "started_at" => ts, "finished_at" => ts, "exit_code" => 1, "log_excerpt" => "boom" }

    expect { described_class.new(server).call([ third ]) }.to have_enqueued_job(NotifyJob) # 3rd real failure fires
    expect { described_class.new(server).call([ third ]) }.not_to have_enqueued_job(NotifyJob) # retry: idempotent skip

    expect(task.runs.count).to eq(3)
  end

  it "ignores skipped runs for streak counting" do
    notification
    record(1); record(1)
    described_class.new(server).call([ { "task_id" => task.id, "started_at" => next_tick,
      "skipped_reason" => "overlap" } ])
    expect { record(1) }.to have_enqueued_job(NotifyJob)
  end
end
