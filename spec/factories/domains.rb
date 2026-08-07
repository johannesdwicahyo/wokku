# frozen_string_literal: true

FactoryBot.define do
  factory :domain do
    association :app_record
    sequence(:hostname) { |n| "app#{n}.example.com" }
  end
end
