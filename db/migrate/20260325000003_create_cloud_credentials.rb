class CreateCloudCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :cloud_credentials do |t|
      t.references :team, null: false, foreign_key: true
      t.string :provider, null: false  # hetzner, vultr, digitalocean, linode
      t.string :name
      t.string :api_key
      t.timestamps
    end
    add_index :cloud_credentials, [:team_id, :provider]

    add_column :servers, :cloud_provider, :string
    add_column :servers, :cloud_server_id, :string
    add_column :servers, :monthly_cost_cents, :integer
  end
end
