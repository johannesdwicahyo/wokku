class AddProviderToDeviceTokens < ActiveRecord::Migration[8.1]
  def change
    # Constant default: existing rows read as expo with no rewrite.
    add_column :device_tokens, :provider, :string, null: false, default: "expo"
  end
end
