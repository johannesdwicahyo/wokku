class AddBalanceToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :balance_idr, :integer, default: 0, null: false
    add_column :users, :balance_usd_cents, :integer, default: 0, null: false
    add_column :users, :payment_method_type, :string, default: "none"
  end
end
