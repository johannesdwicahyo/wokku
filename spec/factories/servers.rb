# frozen_string_literal: true

FactoryBot.define do
  factory :server do
    sequence(:name) { |n| "server-#{n}" }
    sequence(:host) { |n| "10.0.#{n / 256}.#{n % 256}" }
    port { 22 }
    ssh_user { "dokku" }
    status { :connected }
    association :team
  end
end
