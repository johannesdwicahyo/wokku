class AddApiTokenToDeviceTokens < ActiveRecord::Migration[8.1]
  def change
    add_reference :device_tokens, :api_token, type: :uuid, null: true, foreign_key: true, index: true
  end
end
