class AddNewColumnsToPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :plans, :key,                    :string,  null: false, default: ""
    add_column :plans, :price_usd_cents,        :integer, null: false, default: 0
    add_column :plans, :price_idr,              :integer, null: false, default: 0
    add_column :plans, :seats_included,         :integer, null: false, default: 1
    add_column :plans, :extra_seat_usd_cents,   :integer, null: false, default: 0
    add_column :plans, :slot_quotas,            :jsonb,   null: false, default: {}
    add_column :plans, :addons_available,       :jsonb,   null: false, default: {}
    add_column :plans, :backup_policy,          :string,  null: false, default: "manual"
    add_column :plans, :backup_retention_days,  :integer, null: false, default: 0
    add_column :plans, :support_level,          :string,  null: false, default: "chatbot"
    add_column :plans, :pro_features,           :jsonb,   null: false, default: []

    # Backfill `key` for existing rows BEFORE adding the unique index.
    # Production rolled into Phase 4 with the legacy plan names
    # (free / hobby / professional / enterprise); without this step the
    # unique-index migration crashes on duplicate empty strings. Mapping
    # mirrors the Phase 4 rename. Unknown names fall through downcased so
    # the index can still be built; the post-deploy seed pass (running
    # db/seeds/plans.rb's find_or_initialize_by(key:) upsert) restores
    # the canonical Plan attributes after this.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE plans SET key =
            CASE LOWER(name)
              WHEN 'free'         THEN 'free'
              WHEN 'hobby'        THEN 'solo'
              WHEN 'professional' THEN 'pro'
              WHEN 'enterprise'   THEN 'team'
              ELSE LOWER(name)
            END
          WHERE key IS NULL OR key = ''
        SQL
      end
    end

    add_index :plans, :key, unique: true
  end
end
