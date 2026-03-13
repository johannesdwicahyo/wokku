class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :plan, null: false, foreign_key: true
      t.integer :status, default: 0, null: false
      t.string :stripe_subscription_id
      t.datetime :current_period_end

      t.timestamps
    end
  end
end
