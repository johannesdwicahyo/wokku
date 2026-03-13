class CreateServers < ActiveRecord::Migration[8.1]
  def change
    create_table :servers do |t|
      t.string :name, null: false
      t.string :host, null: false
      t.integer :port, default: 22
      t.string :ssh_user, default: "dokku"
      t.text :ssh_private_key
      t.references :team, null: false, foreign_key: true
      t.integer :status, default: 0

      t.timestamps
    end

    add_index :servers, [:name, :team_id], unique: true
  end
end
