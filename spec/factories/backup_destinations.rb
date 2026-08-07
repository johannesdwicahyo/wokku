FactoryBot.define do
  factory :backup_destination do
    association :server
    bucket { "test-bucket" }
    region { "us-east-1" }
    retention_days { 30 }
    provider { "s3" }
  end
end
