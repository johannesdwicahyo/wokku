class RenameSlotQuotasToBoxQuotas < ActiveRecord::Migration[8.1]
  def change
    rename_column :plans, :slot_quotas, :box_quotas
  end
end
