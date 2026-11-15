# frozen_string_literal: true

FactoryBot.define do
  factory :object_storage_bucket do
    association :app_record
    team { app_record.team }
    sequence(:name) { |n| "wk-#{n.to_s.rjust(12, "0")}" }
    access_key { "wk#{SecureRandom.hex(9)}" }
    secret_key { SecureRandom.alphanumeric(40) }
    quota_gb { 10 }
    status { "active" }
  end
end
