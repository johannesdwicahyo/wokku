class EncryptWebhookSecretsAndDeviceTokens < ActiveRecord::Migration[8.1]
  # Backfill encryption for three columns we just added `encrypts` to:
  #   AppRecord.git_webhook_secret, AppRecord.github_webhook_secret,
  #   DeviceToken.token.
  #
  # Schema doesn't change — `encrypts` only affects the model layer. This
  # migration walks existing rows and re-saves them so the plaintext values
  # in the DB get replaced with their encrypted form.
  #
  # `support_unencrypted_data: true` (see config/application.rb) keeps reads
  # working during the brief window between deploying the new code and this
  # migration running.

  def up
    AppRecord.reset_column_information
    AppRecord.where("git_webhook_secret IS NOT NULL OR github_webhook_secret IS NOT NULL").find_each do |app|
      app.encrypt
    end

    DeviceToken.reset_column_information
    DeviceToken.find_each(&:encrypt)
  end

  def down
    # No-op. Rolling back the model change would leave encrypted values in
    # the DB that the app couldn't read anymore, so we don't try to decrypt
    # in reverse. Restore from backup if needed.
  end
end
