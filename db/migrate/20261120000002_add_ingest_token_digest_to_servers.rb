class AddIngestTokenDigestToServers < ActiveRecord::Migration[8.1]
  # F-10: agents are looked up by SHA-256(ingest_token), not the token itself.
  def up
    add_column :servers, :ingest_token_digest, :string
    execute "UPDATE servers SET ingest_token_digest = encode(sha256(convert_to(ingest_token, 'UTF8')), 'hex') WHERE ingest_token IS NOT NULL"
    add_index :servers, :ingest_token_digest, unique: true
  end

  def down
    remove_column :servers, :ingest_token_digest
  end
end
