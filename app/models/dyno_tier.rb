class DynoTier < ApplicationRecord
  has_many :dyno_allocations

  validates :name, presence: true, uniqueness: true
  validates :memory_mb, :cpu_shares, :price_cents_per_month,
    presence: true,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :paid, -> { where(sleeps: false) }

  def price_per_month
    price_cents_per_month / 100.0
  end
end
