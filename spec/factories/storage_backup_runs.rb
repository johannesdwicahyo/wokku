FactoryBot.define do
  factory :storage_backup_run do
    server
    kind { "sync" }
    status { "ok" }
  end
end
