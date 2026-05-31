class BackfillServerIngestTokens < ActiveRecord::Migration[8.1]
  def up
    Server.reset_column_information
    Server.where(ingest_token: nil).find_each do |server|
      server.update_column(:ingest_token, SecureRandom.hex(32))
    end
  end

  def down
    # No-op. Tokens stay where they are; setting them to nil would
    # break any Vector instance configured with the prior token.
  end
end
