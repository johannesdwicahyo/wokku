FactoryBot.define do
  factory :database_service do
    sequence(:name) { |n| "db-#{n}" }
    service_type { "postgres" }
    association :server
    shared { false }
  end
end
