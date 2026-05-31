class AddOnboardingToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :onboarding_status, :integer, default: 0, null: false
    add_column :users, :onboarding_step, :integer, default: 0, null: false
    # Existing users are not first-run — do not retro-show the tour.
    # 2 == completed (see enum in User model).
    execute "UPDATE users SET onboarding_status = 2"
  end

  def down
    remove_column :users, :onboarding_step
    remove_column :users, :onboarding_status
  end
end
