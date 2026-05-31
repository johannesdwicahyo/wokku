require "rails_helper"

RSpec.describe LogRetentionPruneJob do
  let(:server)    { servers(:one) }
  let(:free_app)  { app_records(:one) }
  let(:solo_app)  { app_records(:two) }
  let(:solo_plan) { Plan.find_by!(key: "solo") }

  before do
    Subscription.create!(user: solo_app.creator, plan: solo_plan, status: :active,
                         current_period_end: 1.month.from_now)
  end

  def make_log(app:, ts:, container: "x.web.1")
    Log.create!(server: app.server, app_record: app, container: container, ts: ts, line: "hi")
  end

  it "deletes Free-app logs older than 1 day" do
    fresh = make_log(app: free_app, ts: 1.hour.ago)
    stale = make_log(app: free_app, ts: 2.days.ago)
    described_class.new.perform
    expect(Log.exists?(fresh.id)).to be(true)
    expect(Log.exists?(stale.id)).to be(false)
  end

  it "keeps Solo-app logs younger than 3 days" do
    keep = make_log(app: solo_app, ts: 2.days.ago)
    drop = make_log(app: solo_app, ts: 4.days.ago)
    described_class.new.perform
    expect(Log.exists?(keep.id)).to be(true)
    expect(Log.exists?(drop.id)).to be(false)
  end

  it "applies the orphan fallback (30d) to logs with no app_record_id" do
    fresh = Log.create!(server: server, container: "dokku-postgres.svc", ts: 10.days.ago, line: "hi", app_record: nil)
    stale = Log.create!(server: server, container: "dokku-postgres.svc", ts: 40.days.ago, line: "hi", app_record: nil)
    described_class.new.perform
    expect(Log.exists?(fresh.id)).to be(true)
    expect(Log.exists?(stale.id)).to be(false)
  end

  it "returns a summary hash with per-plan counts" do
    make_log(app: free_app, ts: 5.days.ago)
    make_log(app: solo_app, ts: 5.days.ago)
    result = described_class.new.perform
    expect(result[:by_plan]).to include("free", "solo")
    expect(result[:by_plan]["free"]).to eq(1)
    expect(result[:by_plan]["solo"]).to eq(1)
  end
end
