# frozen_string_literal: true

FactoryBot.define do
  factory :crash_event do
    association :app_record
    sequence(:container_id) { |n| "app.web.1.#{n}" }
    exit_code { 1 }
    oom_killed { false }
    exited_at { Time.current }
    log_excerpt { "boom" }
  end
end
