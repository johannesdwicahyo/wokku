FactoryBot.define do
  factory :scheduled_task do
    app_record
    command     { "echo hello" }
    schedule    { "0 3 * * *" }
    description { "Nightly job" }
    enabled     { true }
  end
end
