FactoryBot.define do
  factory :scheduled_task_run do
    scheduled_task
    started_at { Time.current }
    finished_at { Time.current }
    exit_code { 0 }
  end
end
