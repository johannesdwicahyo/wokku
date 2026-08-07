# frozen_string_literal: true

FactoryBot.define do
  factory :dyno_allocation do
    association :app_record
    association :dyno_tier
    process_type { "web" }
    count { 1 }
  end
end
