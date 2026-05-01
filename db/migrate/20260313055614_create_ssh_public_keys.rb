class CreateSshPublicKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :ssh_public_keys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :public_key, null: false
      t.string :fingerprint, null: false

      t.timestamps
    end
    add_index :ssh_public_keys, :fingerprint, unique: true
  end
end
