# frozen_string_literal: true

FactoryBot.define do
  factory :dyno_tier do
    sequence(:name) { |n| "tier-#{n}" }
    memory_mb { 512 }
    cpu_shares { 0.5 }
    monthly_price_cents { 0 }
    price_cents_per_hour { 0.0 }
    sleeps { false }
    scalable { false }
    # size_key is derived (DynoTier#size_key from name, else memory bucket);
    # memory_mb 512 → "small". Not a settable attribute.
  end
end
