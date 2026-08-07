FactoryBot.define do
  factory :plan do
    sequence(:key) { |n| "plan_#{n}" }
    name { "Test Plan" }
    price_usd_cents { 0 }
    price_idr { 0 }
    seats_included { 1 }
    box_quotas { { "small" => 0, "medium" => 0, "large" => 0, "xlarge" => 0, "sleeping" => 0 } }
    addons_available { {} }
    backup_policy { "manual" }
    backup_retention_days { 0 }
    support_level { "chatbot" }
    pro_features { [] }

    # Named traits coexist with the global plans fixture by adopting the
    # existing row (if any) and overlaying the trait attributes — so
    # `create(:plan, :solo)` returns the canonical Solo plan with the
    # quotas this spec needs, regardless of whether fixtures or a prior
    # build already created it.
    trait :free do
      key  { "free" }
      name { "Free" }
      box_quotas { { "sleeping" => 3 } }
      initialize_with { Plan.find_or_initialize_by(key: "free") }
    end

    trait :solo do
      key  { "solo" }
      name { "Solo" }
      price_usd_cents { 500 }
      box_quotas       { { "small" => 3, "sleeping" => 3 } }
      backup_policy    { "daily" }
      backup_retention_days { 3 }
      initialize_with { Plan.find_or_initialize_by(key: "solo") }
    end

    trait :pro do
      key  { "pro" }
      name { "Pro" }
      price_usd_cents { 2000 }
      price_idr        { 300_000 }
      box_quotas       { { "small" => 3, "medium" => 2, "sleeping" => 3 } }
      backup_policy    { "daily" }
      backup_retention_days { 7 }
      pro_features    { %w[pr_previews transfer_app scheduled_tasks] }
      initialize_with { Plan.find_or_initialize_by(key: "pro") }
    end

    trait :team do
      key  { "team" }
      name { "Team" }
      price_usd_cents { 5000 }
      box_quotas       { { "small" => 3, "medium" => 2, "large" => 1, "sleeping" => 3 } }
      addons_available { {
        "small"  => { "idr" => 30_000,  "usd_cents" => 200  },
        "medium" => { "idr" => 75_000,  "usd_cents" => 500  },
        "large"  => { "idr" => 150_000, "usd_cents" => 1000 },
        "xlarge" => { "idr" => 300_000, "usd_cents" => 2000 }
      } }
      backup_policy    { "daily_plus_monthly" }
      backup_retention_days { 30 }
      pro_features    { %w[pr_previews transfer_app scheduled_tasks] }
      initialize_with { Plan.find_or_initialize_by(key: "team") }
    end
  end
end
