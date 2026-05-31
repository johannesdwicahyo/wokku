class AddPlanToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :plan, type: :uuid, foreign_key: true, null: true
  end
end
