# frozen_string_literal: true

FactoryBot.define do
  factory :alert_mute do
    association :user
    event { "app_down" }
  end
end
