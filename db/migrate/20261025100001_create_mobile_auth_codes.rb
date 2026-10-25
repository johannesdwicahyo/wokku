class CreateMobileAuthCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :mobile_auth_codes, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :code_digest, null: false
      t.string :code_challenge, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end
    add_index :mobile_auth_codes, :code_digest, unique: true
  end
end
