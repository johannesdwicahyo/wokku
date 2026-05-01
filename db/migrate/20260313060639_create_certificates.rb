class CreateCertificates < ActiveRecord::Migration[8.1]
  def change
    create_table :certificates do |t|
      t.references :domain, null: false, foreign_key: true
      t.datetime :expires_at
      t.boolean :auto_renew, default: true

      t.timestamps
    end
  end
end
