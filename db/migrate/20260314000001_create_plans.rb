class CreatePlans < ActiveRecord::Migration[8.1]
  def change
    create_table :plans do |t|
      t.string :name, null: false
      t.integer :max_apps, null: false
      t.integer :max_dynos
      t.integer :max_databases
      t.integer :price_cents_per_month
      t.string :stripe_price_id

      t.timestamps
    end

    add_index :plans, :name, unique: true
    add_index :plans, :stripe_price_id, unique: true
  end
end
