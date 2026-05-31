# frozen_string_literal: true

FactoryBot.define do
  factory :app_record do
    sequence(:name) { |n| "app-#{n}" }
    association :team
    association :server
    association :creator, factory: :user
    deploy_branch { "main" }
    is_preview { false }
    status { :running }

    trait :preview do
      is_preview { true }
      sequence(:pr_number) { |n| n }
      association :parent_app, factory: :app_record
    end
  end
end
