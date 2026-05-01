require "test_helper"

class ActivityDigestTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @team = teams(:one)
    # Test DB now loads from structure.sql which preserves the append-only
    # triggers. These tests need to bypass them to simulate tampering and
    # to test trigger installation explicitly.
    drop_activity_triggers
  end

  teardown { drop_activity_triggers }

  def drop_activity_triggers
    conn = ActiveRecord::Base.connection
    %w[activities_no_update activities_no_delete activities_no_truncate].each do |trig|
      conn.execute("DROP TRIGGER IF EXISTS #{trig} ON activities")
    end
  end

  test "chain_hash is deterministic for the same activity set" do
    d = Date.new(2026, 4, 10)
    travel_to d.to_time + 9.hours do
      Activity.log(user: @user, team: @team, action: "test.one", metadata: { a: 1 })
      Activity.log(user: @user, team: @team, action: "test.two", metadata: { b: 2 })
    end

    h1 = ActivityDigest.compute_for(d)[:chain_hash]
    h2 = ActivityDigest.compute_for(d)[:chain_hash]
    assert_equal h1, h2
    assert_equal 64, h1.length
  end

  test "chain_hash changes if any activity field changes" do
    d = Date.new(2026, 4, 11)
    travel_to d.to_time + 9.hours do
      Activity.log(user: @user, team: @team, action: "test.original", metadata: {})
    end
    before = ActivityDigest.compute_for(d)[:chain_hash]

    # Simulate tamper (in prod the trigger blocks this; in test we've
    # deliberately skipped the trigger so we can still verify the hash
    # catches changes).
    ActiveRecord::Base.connection.execute(
      "UPDATE activities SET action = 'tampered' WHERE action = 'test.original'"
    )
    after = ActivityDigest.compute_for(d)[:chain_hash]
    assert_not_equal before, after, "tampering must be detectable via digest mismatch"
  end

  test "append-only trigger blocks updates when installed" do
    sql = File.read(Rails.root.join("db/migrate/20260421203418_make_activities_append_only.rb"))
    create_sql = sql[/CREATE OR REPLACE FUNCTION.*?TRIGGER activities_no_truncate.*?FUNCTION wokku_block_activity_mutation\(\);/m]
    skip "trigger SQL not found in migration" unless create_sql

    conn = ActiveRecord::Base.connection
    conn.execute(create_sql)
    begin
      Activity.log(user: @user, team: @team, action: "blocked.test", metadata: {})
      # Each failing statement aborts the test's surrounding transaction;
      # wrap in savepoints so the second assertion can still run.
      assert_raises ActiveRecord::StatementInvalid do
        conn.transaction(requires_new: true) do
          conn.execute("UPDATE activities SET action = 'nope' WHERE action = 'blocked.test'")
        end
      end
      assert_raises ActiveRecord::StatementInvalid do
        conn.transaction(requires_new: true) do
          conn.execute("DELETE FROM activities WHERE action = 'blocked.test'")
        end
      end
    ensure
      conn.execute(<<~SQL)
        DROP TRIGGER IF EXISTS activities_no_update    ON activities;
        DROP TRIGGER IF EXISTS activities_no_delete    ON activities;
        DROP TRIGGER IF EXISTS activities_no_truncate  ON activities;
        DROP FUNCTION IF EXISTS wokku_block_activity_mutation;
      SQL
    end
  end

  test "each day's hash chains from the previous" do
    d1 = Date.new(2026, 4, 12)
    d2 = d1.next_day
    travel_to d1.to_time + 10.hours do
      Activity.log(user: @user, team: @team, action: "day1.one", metadata: {})
    end
    travel_to d2.to_time + 10.hours do
      Activity.log(user: @user, team: @team, action: "day2.one", metadata: {})
    end

    digest1 = ActivityDigest.record_for!(d1)
    digest2 = ActivityDigest.record_for!(d2)

    assert_equal digest1.chain_hash, digest2.prev_hash
    assert_not_equal digest1.chain_hash, digest2.chain_hash
  end
end
