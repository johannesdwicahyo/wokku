FactoryBot.define do
  factory :backup do
    association :database_service
    association :backup_destination
    status { "completed" }
    sequence(:s3_key) { |n| "dbs/x/#{n}.gz" }

    trait :volume do
      kind { :volume }
      database_service { nil }
      mount_path { "/var/lib/dokku/data/storage/myapp/data" }
    end
  end
end
