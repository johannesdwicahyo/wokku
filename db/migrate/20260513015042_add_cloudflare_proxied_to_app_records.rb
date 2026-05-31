class AddCloudflareProxiedToAppRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :app_records, :cloudflare_proxied, :boolean, default: false, null: false
  end
end
