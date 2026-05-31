FactoryBot.define do
  factory :app_database do
    association :app_record
    association :database_service
    alias_name { "DATABASE" }
  end
end
