class CreatePromoCodesAndRedemptions < ActiveRecord::Migration[8.1]
  def change
    create_table :promo_codes, id: :uuid do |t|
      t.string  :code,                null: false
      # manual_credit  → Phase 1 (admin DM, instant credit, no deposit needed)
      # channel_match  → Phase 2 (public code per channel, bonus on first deposit)
      # referral       → Phase 3 (auto-generated per user, 2-sided rewards)
      t.string  :kind,                null: false
      t.integer :redeemer_bonus_idr,  null: false, default: 0
      t.integer :inviter_bonus_idr,   null: false, default: 0
      t.references :inviter_user,     foreign_key: { to_table: :users }, type: :uuid
      t.integer :min_deposit_idr,     null: false, default: 0
      t.integer :max_redemptions
      t.integer :redemptions_count,   null: false, default: 0
      t.datetime :expires_at
      t.references :created_by,       foreign_key: { to_table: :users }, type: :uuid
      t.text     :description
      t.boolean  :active,             null: false, default: true
      t.timestamps
    end
    add_index :promo_codes, :code, unique: true
    add_index :promo_codes, :kind

    create_table :promo_redemptions, id: :uuid do |t|
      t.references :promo_code,                       null: false, foreign_key: true, type: :uuid
      t.references :redeemer_user,                    null: false, foreign_key: { to_table: :users }, type: :uuid
      # pending → applied on a qualifying deposit
      # applied → bonus paid out, terminal
      # void    → cancelled (e.g., conflicting refund) — terminal
      t.string   :status,                             null: false, default: "pending"
      t.datetime :applied_at
      t.references :triggered_by_deposit,             foreign_key: { to_table: :deposit_transactions }, type: :uuid
      t.integer  :redeemer_bonus_idr_snapshot,        null: false, default: 0
      t.integer  :inviter_bonus_idr_snapshot,         null: false, default: 0
      t.timestamps
    end
    add_index :promo_redemptions, [ :redeemer_user_id, :promo_code_id ], unique: true, name: "idx_promo_redemptions_unique_per_user_code"
    add_index :promo_redemptions, :status
  end
end
