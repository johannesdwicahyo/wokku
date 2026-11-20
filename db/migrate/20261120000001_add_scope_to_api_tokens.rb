class AddScopeToApiTokens < ActiveRecord::Migration[8.1]
  # F-02: read tokens can only look; full tokens work as before (the default,
  # so every existing token and login keeps its power).
  def change
    add_column :api_tokens, :scope, :string, null: false, default: "full"
    add_check_constraint :api_tokens, "scope IN ('read', 'full')", name: "api_tokens_scope_check"
  end
end
