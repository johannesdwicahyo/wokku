# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user-#{n}@test.local" }
    password { "supersecret123" }
    password_confirmation { "supersecret123" }
    role { :member }
    currency { "idr" }
    locale { "en" }
    payment_method_type { "deposit" }
    deleted_at { nil }
    deletion_scheduled_at { nil }

    trait :admin do
      role { :admin }
    end

    trait :pending_deletion do
      deletion_scheduled_at { 2.days.from_now }
    end

    trait :hard_deleted do
      deleted_at { 1.hour.ago }
    end

    # `:with_funds` removed in 1.8 with the balance columns. Use a
    # `create(:invoice, status: :paid, ...)` instead to mark a paid user.

    # Opt-in: mirror billing state onto a personal team so
    # `user.current_plan / on_trial? / next_billing_date` resolve via
    # the strict-delegate path. NOT default — pure `create(:user)`
    # leaves the user team-less so auth/authorization short-circuits
    # behave as before.
    trait :with_personal_team do
      after(:create) do |user, _evaluator|
        next if user.teams.exists?
        team = Team.create!(
          name: "#{user.email}-team",
          owner: user, kind: :personal,
          slug: "ws-#{SecureRandom.hex(4)}",
          plan: user.plan || Plan.find_by(key: "free"),
          trial_ends_at: user.trial_ends_at,
          billing_anchor_date: user.billing_anchor_date,
          payment_method_type: user.payment_method_type || "none"
        )
        TeamMembership.create!(user: user, team: team, role: :admin)
      end
    end
  end
end
