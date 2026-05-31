# frozen_string_literal: true

FactoryBot.define do
  factory :team_membership do
    association :team
    association :user
    role { :member }
  end
end
