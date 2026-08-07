require "rails_helper"

RSpec.describe ActivityDigest do
  let(:user) { users(:one) }
  let(:team) { teams(:one) }

  def drop_activity_triggers
    conn = ActiveRecord::Base.connection
    %w[activities_no_update activities_no_delete activities_no_truncate].each do |trig|
      conn.execute("DROP TRIGGER IF EXISTS #{trig} ON activities")
    end
  end

  # Test DB now loads from structure.sql which preserves the append-only
  # triggers. These tests need to bypass them to simulate tampering and
  # to test trigger installation explicitly.
  before { drop_activity_triggers }
  after  { drop_activity_triggers }

  it "chain_hash is deterministic for the same activity set" do
    d = Date.new(2026, 4, 10)
    travel_to d.to_time + 9.hours do
      Activity.log(user: user, team: team, action: "test.one", metadata: { a: 1 })
      Activity.log(user: user, team: team, action: "test.two", metadata: { b: 2 })
    end

    h1 = ActivityDigest.compute_for(d)[:chain_hash]
    h2 = ActivityDigest.compute_for(d)[:chain_hash]
    expect(h1).to eq(h2)
    expect(h1.length).to eq(64)
  end

  it "chain_hash changes if any activity field changes" do
    d = Date.new(2026, 4, 11)
    travel_to d.to_time + 9.hours do
      Activity.log(user: user, team: team, action: "test.original", metadata: {})
    end
    before_hash = ActivityDigest.compute_for(d)[:chain_hash]

    ActiveRecord::Base.connection.execute(
      "UPDATE activities SET action = 'tampered' WHERE action = 'test.original'"
    )
    after_hash = ActivityDigest.compute_for(d)[:chain_hash]
    expect(after_hash).not_to eq(before_hash), "tampering must be detectable via digest mismatch"
  end

  it "append-only trigger blocks updates when installed" do
    migration = Dir[Wokku::Engine.root.join("db/migrate/*make_activities_append_only.rb")].first
    skip "append-only migration not present" unless migration
    sql = File.read(migration)
    create_sql = sql[/CREATE OR REPLACE FUNCTION.*?TRIGGER activities_no_truncate.*?FUNCTION wokku_block_activity_mutation\(\);/m]
    skip "trigger SQL not found in migration" unless create_sql

    conn = ActiveRecord::Base.connection
    conn.execute(create_sql)
    begin
      Activity.log(user: user, team: team, action: "blocked.test", metadata: {})
      expect {
        conn.transaction(requires_new: true) do
          conn.execute("UPDATE activities SET action = 'nope' WHERE action = 'blocked.test'")
        end
      }.to raise_error(ActiveRecord::StatementInvalid)
      expect {
        conn.transaction(requires_new: true) do
          conn.execute("DELETE FROM activities WHERE action = 'blocked.test'")
        end
      }.to raise_error(ActiveRecord::StatementInvalid)
    ensure
      conn.execute(<<~SQL)
        DROP TRIGGER IF EXISTS activities_no_update    ON activities;
        DROP TRIGGER IF EXISTS activities_no_delete    ON activities;
        DROP TRIGGER IF EXISTS activities_no_truncate  ON activities;
        DROP FUNCTION IF EXISTS wokku_block_activity_mutation;
      SQL
    end
  end

  it "each day's hash chains from the previous" do
    d1 = Date.new(2026, 4, 12)
    d2 = d1.next_day
    travel_to d1.to_time + 10.hours do
      Activity.log(user: user, team: team, action: "day1.one", metadata: {})
    end
    travel_to d2.to_time + 10.hours do
      Activity.log(user: user, team: team, action: "day2.one", metadata: {})
    end

    digest1 = ActivityDigest.record_for!(d1)
    digest2 = ActivityDigest.record_for!(d2)

    expect(digest2.prev_hash).to eq(digest1.chain_hash)
    expect(digest2.chain_hash).not_to eq(digest1.chain_hash)
  end
end
