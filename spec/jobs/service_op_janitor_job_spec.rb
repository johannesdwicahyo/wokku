# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServiceOpJanitorJob, type: :job do
  it "reaps ops wedged at claimed past REAP_AFTER (dead agent)" do
    wedged = create(:service_op, status: :claimed, claimed_at: 40.minutes.ago)
    fresh  = create(:service_op, status: :claimed, claimed_at: 5.minutes.ago)

    described_class.perform_now

    expect(wedged.reload).to be_failed
    expect(wedged.error_code).to eq("reaped")
    expect(wedged.finished_at).to be_present
    expect(fresh.reload).to be_claimed
  end

  it "prunes terminal ops past PRUNE_AFTER, keeps recent and non-terminal ones" do
    old_done = create(:service_op, status: :succeeded, finished_at: 31.days.ago)
    recent   = create(:service_op, status: :failed, finished_at: 2.days.ago)
    pending  = create(:service_op) # pending, no finished_at — never pruned

    expect { described_class.perform_now }.to change(ServiceOp, :count).by(-1)

    expect(ServiceOp.exists?(old_done.id)).to be false
    expect(ServiceOp.exists?(recent.id)).to be true
    expect(ServiceOp.exists?(pending.id)).to be true
  end

  it "reaps lifecycle ops wedged at claimed past REAP_AFTER (dead agent)" do
    wedged = create(:lifecycle_op, status: :claimed, claimed_at: 40.minutes.ago)
    fresh  = create(:lifecycle_op, status: :claimed, claimed_at: 5.minutes.ago)

    described_class.perform_now

    expect(wedged.reload).to be_failed
    expect(wedged.error_code).to eq("reaped")
    expect(wedged.finished_at).to be_present
    expect(fresh.reload).to be_claimed
  end

  it "prunes terminal lifecycle ops past PRUNE_AFTER, keeps recent and non-terminal ones" do
    old_done = create(:lifecycle_op, status: :succeeded, finished_at: 31.days.ago)
    recent   = create(:lifecycle_op, status: :failed, finished_at: 2.days.ago)
    pending  = create(:lifecycle_op) # pending, no finished_at — never pruned

    expect { described_class.perform_now }.to change(LifecycleOp, :count).by(-1)

    expect(LifecycleOp.exists?(old_done.id)).to be false
    expect(LifecycleOp.exists?(recent.id)).to be true
    expect(LifecycleOp.exists?(pending.id)).to be true
  end

  # I3: never-claimed pending ops wedge the lane forever — reap the stale ones.
  it "reaps a stale PENDING op (never claimed) but leaves a fresh pending untouched" do
    stale = create(:lifecycle_op, status: :pending, created_at: 40.minutes.ago)
    fresh = create(:lifecycle_op, status: :pending, created_at: 5.minutes.ago)

    described_class.perform_now

    expect(stale.reload).to be_failed
    expect(stale.error_code).to eq("reaped_pending")
    expect(stale.finished_at).to be_present
    expect(fresh.reload).to be_pending
  end

  it "reaps a stale pending ServiceOp with error_code reaped_pending" do
    stale = create(:service_op, status: :pending, created_at: 40.minutes.ago)
    described_class.perform_now
    expect(stale.reload).to be_failed
    expect(stale.error_code).to eq("reaped_pending")
  end

  # I5: a reaped row never went through #report, so redact its secrets here.
  it "redacts env on a reaped LifecycleOp" do
    op = create(:lifecycle_op, status: :claimed, claimed_at: 40.minutes.ago,
                               params: { "image_ref" => "x", "env" => { "SECRET" => "shh" } })
    described_class.perform_now
    expect(op.reload.params["env"]).to eq("[REDACTED]")
    expect(op.params["image_ref"]).to eq("x")
  end

  it "redacts password and presigned URLs on a reaped ServiceOp" do
    op = create(:service_op, status: :pending, created_at: 40.minutes.ago,
                             params: { "service_type" => "postgres", "password" => "pw",
                                       "presigned_put_url" => "https://x", "presigned_get_url" => "https://y" })
    described_class.perform_now
    op.reload
    expect(op.params["password"]).to eq("[REDACTED]")
    expect(op.params["presigned_put_url"]).to eq("[REDACTED]")
    expect(op.params["presigned_get_url"]).to eq("[REDACTED]")
    expect(op.params["service_type"]).to eq("postgres")
  end
end
