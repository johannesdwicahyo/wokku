require "rails_helper"

RSpec.describe RequestAggregateRetentionPruneJob do
  let(:free_app) { app_records(:one) }
  let(:solo_app) { app_records(:two) }
  let(:solo_plan) { Plan.find_by!(key: "solo") }

  before do
    Subscription.create!(user: solo_app.creator, plan: solo_plan, status: :active,
                         current_period_end: 1.month.from_now)
  end

  def make_agg(app, t)
    RequestAggregate.create!(
      app_record: app, bucket_start: t,
      req_count: 1, p50_ms: 10, p95_ms: 20,
      error_4xx: 0, error_5xx: 0, bytes_sent_total: 100
    )
  end

  it "deletes Free aggregates older than 7 days but keeps fresh ones" do
    fresh = make_agg(free_app, 2.days.ago)
    stale = make_agg(free_app, 10.days.ago)
    described_class.new.perform
    expect(RequestAggregate.exists?(fresh.id)).to be(true)
    expect(RequestAggregate.exists?(stale.id)).to be(false)
  end

  it "keeps Solo aggregates up to 30 days" do
    keep = make_agg(solo_app, 25.days.ago)
    drop = make_agg(solo_app, 40.days.ago)
    described_class.new.perform
    expect(RequestAggregate.exists?(keep.id)).to be(true)
    expect(RequestAggregate.exists?(drop.id)).to be(false)
  end
end
