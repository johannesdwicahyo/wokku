class Invoice < ApplicationRecord
  belongs_to :user

  enum :status, { pending: 0, paid: 1, failed: 2, refunded: 3 }
end
