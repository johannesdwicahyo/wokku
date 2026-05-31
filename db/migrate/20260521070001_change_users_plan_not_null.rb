class ChangeUsersPlanNotNull < ActiveRecord::Migration[8.1]
  def up
    change_column_null :users, :plan_id, false
  end

  def down
    change_column_null :users, :plan_id, true
  end
end
