class Plan < ApplicationRecord
  has_many :subscriptions

  validates :name, presence: true, uniqueness: true
  validates :max_apps, :max_dynos, :max_databases, :price_cents_per_month,
            presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def free?
    price_cents_per_month == 0
  end
end
