# frozen_string_literal: true

FactoryBot.define do
  factory :incident do
    association :app_record
    reason { "http_5xx" }
    started_at { Time.current }

    trait :for_server do
      app_record { nil }
      association :server
    end
  end
end
