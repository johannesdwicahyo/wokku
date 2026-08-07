# frozen_string_literal: true

FactoryBot.define do
  factory :notification do
    association :team
    channel { :email }
    # Default to a valid event; examples override with the events they assert on
    events { [ "deploy_succeeded" ] }
  end
end
