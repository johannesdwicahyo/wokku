# frozen_string_literal: true

FactoryBot.define do
  factory :deploy do
    association :app_record
    status { :pending }

    trait :succeeded do
      status { :succeeded }
    end
  end
end
