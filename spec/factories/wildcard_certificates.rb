FactoryBot.define do
  factory :wildcard_certificate do
    fullchain_pem { "FULLCHAIN" }
    key_pem { "KEY" }
    sans { [ "*.wokku.app", "*.wokku.cloud" ] }
    issued_at { Time.current }
    expires_at { 80.days.from_now }
  end
end
