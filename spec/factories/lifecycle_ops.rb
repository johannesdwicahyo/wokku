# frozen_string_literal: true

FactoryBot.define do
  factory :lifecycle_op do
    app_record
    server { app_record.server }
    kind { "stack.converge" }
    params { { "image_ref" => "127.0.0.1:5000/wokku/x:abc" } }
    status { :pending }
  end
end
