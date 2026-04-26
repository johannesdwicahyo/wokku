class MakeActivitiesAppendOnly < ActiveRecord::Migration[8.1]
  # Activities are the audit trail. Block UPDATE / DELETE / TRUNCATE at the
  # database level so an attacker with a DB connection (leaked creds, SQL
  # injection, compromised Rails process) can't rewrite history.
  #
  # INSERT is still allowed. Legitimate rows arrive exclusively via
  # Activity.log; nothing in the app updates or deletes them.

  def up
    # Skip in test: Rails' transactional fixtures clean up with DELETE, which
    # the trigger would block. The trigger is itself exercised by a
    # dedicated test that installs it ad-hoc.
    return if Rails.env.test?

    execute <<~SQL
      CREATE OR REPLACE FUNCTION wokku_block_activity_mutation() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'activities is append-only (attempted %)', TG_OP
          USING ERRCODE = '42501';
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER activities_no_update
        BEFORE UPDATE ON activities
        FOR EACH ROW EXECUTE FUNCTION wokku_block_activity_mutation();

      CREATE TRIGGER activities_no_delete
        BEFORE DELETE ON activities
        FOR EACH ROW EXECUTE FUNCTION wokku_block_activity_mutation();

      CREATE TRIGGER activities_no_truncate
        BEFORE TRUNCATE ON activities
        FOR EACH STATEMENT EXECUTE FUNCTION wokku_block_activity_mutation();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS activities_no_update    ON activities;
      DROP TRIGGER IF EXISTS activities_no_delete    ON activities;
      DROP TRIGGER IF EXISTS activities_no_truncate  ON activities;
      DROP FUNCTION IF EXISTS wokku_block_activity_mutation;
    SQL
  end
end
