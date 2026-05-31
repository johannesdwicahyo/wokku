# OSS stub for Invoice — tableless AR class.
#
# wokku-cloud's Invoice (Stripe + iPaymu billing rows) is stripped from
# OSS. But User#lock_currency_with_active_resources still calls
# `invoices.unpaid.any?` and the `has_many :invoices` association
# triggers autoload of this constant at User class-body load time. We
# ship a tableless stub that always claims zero rows.

class Invoice < ApplicationRecord
  self.table_name = "users" # tableless; AR insists on a real table

  # Force-empty scopes so every billing-flavored callback short-circuits.
  default_scope { none }

  def self.unpaid ; none ; end
  def self.paid   ; none ; end
end
