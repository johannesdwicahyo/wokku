# frozen_string_literal: true

FactoryBot.define do
  factory :team do
    sequence(:name) { |n| "team-#{n}" }
    association :owner, factory: :user
  end
end
