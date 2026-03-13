class CreateDomains < ActiveRecord::Migration[8.1]
  def change
    create_table :domains do |t|
      t.references :app_record, null: false, foreign_key: true
      t.string :hostname
      t.boolean :ssl_enabled, default: false

      t.timestamps
    end

    add_index :domains, :hostname, unique: true
  end
end
