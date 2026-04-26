class AddCurrencyAndFunding < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :currency, :string, default: "usd"
    add_column :users, :locale, :string, default: "en"

    create_table :oss_revenue_shares do |t|
      t.string :template_slug, null: false
      t.string :funding_url
      t.integer :total_cents, default: 0
      t.integer :paid_cents, default: 0
      t.timestamps
    end
    add_index :oss_revenue_shares, :template_slug, unique: true
  end
end
