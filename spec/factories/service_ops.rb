FactoryBot.define do
  factory :service_op do
    database_service
    server { database_service.server }
    kind { "service.create" }
    params { { "service_type" => "postgres" } }
    status { :pending }
  end
end
