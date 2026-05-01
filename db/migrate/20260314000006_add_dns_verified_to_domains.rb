class AddDnsVerifiedToDomains < ActiveRecord::Migration[8.1]
  def change
    add_column :domains, :dns_verified, :boolean, default: false
  end
end
