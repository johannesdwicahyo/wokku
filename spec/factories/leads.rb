# frozen_string_literal: true
FactoryBot.define do
  factory :lead do
    email { "freelancer@example.com" }
    pain_text { "I babysit 5 client VPSes every weekend. SSL keeps expiring." }
    ip { "203.0.113.42" }
    user_agent { "Mozilla/5.0 (test)" }
  end
end
