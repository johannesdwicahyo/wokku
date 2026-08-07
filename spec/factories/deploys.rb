# frozen_string_literal: true

FactoryBot.define do
  factory :deploy do
    association :app_record
    status { :pending }

    trait :succeeded do
      status { :succeeded }
    end

    trait :wokkud do
      builder { "wokkud" }
    end
  end
end
