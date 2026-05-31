class AddBatchToPromoCodes < ActiveRecord::Migration[8.1]
  def change
    add_column :promo_codes, :batch_id, :uuid
    add_column :promo_codes, :batch_label, :string
    add_index  :promo_codes, :batch_id
  end
end
