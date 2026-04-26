class InstallUuidv7Function < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    # Postgres 18 ships uuidv7() natively. Until we're on it, define our
    # own. Time-ordered (millisecond precision in the first 6 bytes), with
    # version=7 and variant=0b10 set per RFC 9562.
    execute <<~SQL
      CREATE OR REPLACE FUNCTION uuidv7() RETURNS uuid AS $$
        SELECT encode(
          set_bit(
            set_bit(
              overlay(uuid_send(gen_random_uuid())
                      placing substring(int8send(floor(extract(epoch from clock_timestamp()) * 1000)::bigint) from 3)
                      from 1 for 6),
              52, 1),
            53, 1),
          'hex')::uuid;
      $$ LANGUAGE sql VOLATILE;
    SQL
  end

  def down
    execute "DROP FUNCTION IF EXISTS uuidv7();"
  end
end
