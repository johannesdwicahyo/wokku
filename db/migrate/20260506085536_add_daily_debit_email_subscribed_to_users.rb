class AddDailyDebitEmailSubscribedToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :daily_debit_email_subscribed, :boolean, default: false, null: false
  end
end
