class CreateLeads < ActiveRecord::Migration[8.1]
  def change
    create_table :leads do |t|
      t.string :email
      t.text :pain_text, null: false
      t.string :ip
      t.string :user_agent, limit: 512
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign
      t.string :utm_content
      t.string :utm_term
      t.string :channel # "form" | "wa"
      t.references :user, type: :uuid, foreign_key: true, null: true
      t.timestamps
    end
    add_index :leads, :created_at
  end
end
