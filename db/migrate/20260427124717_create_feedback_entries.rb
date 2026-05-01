# Public feedback inbox — anyone (signed in or not) can submit.
# Lightweight: name + email + message + page (the URL they were on).
# Nothing fancy yet — when volume justifies it we'll add tagging,
# triage states, etc.
class CreateFeedbackEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :feedback_entries, id: :uuid do |t|
      t.string :name
      t.string :email
      t.text :message, null: false
      t.string :page
      t.string :user_agent
      t.references :user, type: :uuid, foreign_key: true, null: true
      t.timestamps
    end
    add_index :feedback_entries, :created_at
  end
end
