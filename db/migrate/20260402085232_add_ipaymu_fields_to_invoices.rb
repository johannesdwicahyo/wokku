class AddIpaymuFieldsToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :ipaymu_transaction_id, :string unless column_exists?(:invoices, :ipaymu_transaction_id)
    add_column :invoices, :ipaymu_payment_url, :string unless column_exists?(:invoices, :ipaymu_payment_url)
    add_column :invoices, :payment_method, :string unless column_exists?(:invoices, :payment_method)
    add_column :invoices, :due_date, :datetime unless column_exists?(:invoices, :due_date)
    add_column :invoices, :reference_id, :string unless column_exists?(:invoices, :reference_id)
    add_column :invoices, :amount_idr, :integer, default: 0 unless column_exists?(:invoices, :amount_idr)
    add_column :invoices, :period_label, :string unless column_exists?(:invoices, :period_label)

    add_index :invoices, :reference_id, unique: true unless index_exists?(:invoices, :reference_id)
  end
end
