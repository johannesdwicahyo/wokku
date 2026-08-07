FactoryBot.define do
  factory :restore_drill do
    engine { "postgres" }
    status { :passed }
  end
end
