class AddExtraSeatIdrToPlans < ActiveRecord::Migration[8.1]
  def change
    # PR C2 of personal+multi-team refactor: companion to the existing
    # extra_seat_usd_cents column so the IDR launch can charge for
    # over-quota seats. Team plan: Rp 45_000 / extra seat (= $3 spot
    # rate at launch); all other plans 0 (no extra seats sold).
    add_column :plans, :extra_seat_idr, :integer, null: false, default: 0
  end
end
