class AddOtpBackupCodesToUsers < ActiveRecord::Migration[8.1]
  def change
    # Hashed 2FA recovery codes (devise-two-factor :two_factor_backupable).
    add_column :users, :otp_backup_codes, :string, array: true
  end
end
