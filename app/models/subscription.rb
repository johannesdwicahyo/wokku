# OSS stub for Subscription — tableless AR. Team + User both
# `has_many :subscriptions`; the assoc must resolve at class load.
# OSS has no billing → no rows.

class Subscription < ApplicationRecord
  self.table_name = "users" # tableless; AR insists on a real table
  default_scope { none }
end
