# Wokku EE Billing System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a per-hour usage-based billing system where users pay for containers and database plugins at the end of each billing cycle via Stripe.

**Architecture:** Replace the existing plan-based subscription model with per-resource hourly billing. Each billable resource (container, database) tracks usage via `ResourceUsage` records (start/stop timestamps). A monthly `BillingCycleJob` calculates hours consumed, generates a Stripe invoice, and charges the user's saved payment method. Free tier resources require no payment method; paid resources enforce payment method presence before creation.

**Tech Stack:** Rails 8.1, PostgreSQL, Stripe API (metered billing via invoice items), Solid Queue, Tailwind CSS, Hotwire/Turbo

---

## Scope

This plan covers 6 subsystems, each producing working, testable software:

1. **Data Layer** — New models/migrations for hourly pricing and usage tracking
2. **Usage Tracking** — Record start/stop of every billable resource
3. **Billing Engine** — Monthly job to calculate costs and create Stripe invoices
4. **Stripe Integration** — Payment method management, invoice creation, webhook handling
5. **Dashboard UI** — Billing page, plugin management, pricing calculator
6. **Enforcement** — Free tier limits, payment method gates

## File Structure

### New Files (EE)

```
ee/app/models/service_tier.rb              — Pricing tiers for databases (like DynoTier for containers)
ee/app/models/resource_usage.rb            — Tracks start/stop of each billable resource
ee/app/services/billing_calculator.rb      — Calculates hourly costs for a billing period
ee/app/services/stripe_billing.rb          — Stripe API wrapper (customers, payment methods, invoices)
ee/app/jobs/billing_cycle_job.rb           — Monthly job: calculate usage → create Stripe invoice
ee/app/jobs/payment_failure_job.rb         — Handle failed payments: grace period → stop resources
ee/app/controllers/dashboard/payment_methods_controller.rb  — Add/remove payment methods
ee/app/views/dashboard/billing/show.html.erb               — Rewrite: usage-based billing page
ee/app/views/dashboard/billing/_usage_table.html.erb        — Current cycle usage breakdown
ee/app/views/dashboard/billing/_payment_method.html.erb     — Card management partial
ee/app/views/dashboard/billing/_invoice_history.html.erb    — Past invoices list
ee/db/migrate/TIMESTAMP_create_service_tiers.rb
ee/db/migrate/TIMESTAMP_create_resource_usages.rb
ee/db/migrate/TIMESTAMP_update_dyno_tiers_add_hourly_price.rb
ee/db/migrate/TIMESTAMP_add_billing_fields_to_users.rb
```

### Modified Files (EE)

```
ee/app/models/dyno_tier.rb                — Add price_cents_per_hour, update seed data
ee/app/models/concerns/ee_user.rb         — Add resource_usages, payment_method helpers
ee/app/models/concerns/ee_app_record.rb   — Hook into resource tracking on create/destroy
ee/app/controllers/dashboard/billing_controller.rb  — Rewrite for usage-based billing
ee/app/controllers/api/v1/billing_controller.rb     — New endpoints: usage, payment_methods
ee/app/controllers/webhooks/stripe_controller.rb    — Handle invoice.paid/failed events
ee/app/controllers/concerns/plan_enforceable.rb     — Replace plan limits with free tier + payment checks
ee/config/initializers/ee.rb              — Include new concerns, register callbacks
ee/config/routes/ee.rb                    — Add payment_methods routes
ee/app/views/dashboard/shared/_ee_sidebar_items.html.erb  — Already has Billing link
```

### Modified Files (CE)

```
app/views/pages/pricing.html.erb          — Rewrite: per-resource pricing (not plan tiers)
app/controllers/dashboard/databases_controller.rb  — Hook for usage tracking (via callback)
app/controllers/dashboard/apps_controller.rb       — Hook for usage tracking (via callback)
```

---

## Task 1: ServiceTier Model and Migration

**Files:**
- Create: `ee/db/migrate/20260322000001_create_service_tiers.rb`
- Create: `ee/app/models/service_tier.rb`
- Create: `ee/test/models/service_tier_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# ee/test/models/service_tier_test.rb
require "test_helper"

class ServiceTierTest < ActiveSupport::TestCase
  test "valid service tier" do
    tier = ServiceTier.new(
      name: "basic",
      service_type: "postgres",
      price_cents_per_hour: 0.7,
      spec: { storage_gb: 10, connections: 20 }
    )
    assert tier.valid?
  end

  test "requires name and service_type" do
    tier = ServiceTier.new
    assert_not tier.valid?
    assert_includes tier.errors[:name], "can't be blank"
    assert_includes tier.errors[:service_type], "can't be blank"
  end

  test "unique name per service_type" do
    ServiceTier.create!(name: "basic", service_type: "postgres", price_cents_per_hour: 0.7)
    dup = ServiceTier.new(name: "basic", service_type: "postgres", price_cents_per_hour: 0.7)
    assert_not dup.valid?
  end

  test "free? returns true when price is zero" do
    tier = ServiceTier.new(price_cents_per_hour: 0)
    assert tier.free?
  end

  test "monthly_price_cents calculates from hourly" do
    tier = ServiceTier.new(price_cents_per_hour: 0.7)
    assert_equal 511, tier.monthly_price_cents  # 0.7 * 730
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test ee/test/models/service_tier_test.rb`
Expected: FAIL — `NameError: uninitialized constant ServiceTier`

- [ ] **Step 3: Write the migration**

```ruby
# ee/db/migrate/20260322000001_create_service_tiers.rb
class CreateServiceTiers < ActiveRecord::Migration[8.1]
  def change
    create_table :service_tiers do |t|
      t.string :name, null: false
      t.string :service_type, null: false  # postgres, redis, mysql, etc.
      t.decimal :price_cents_per_hour, precision: 10, scale: 4, default: 0, null: false
      t.jsonb :spec, default: {}           # { storage_gb: 10, connections: 20, memory_mb: 256 }
      t.boolean :available, default: true, null: false
      t.timestamps
    end
    add_index :service_tiers, [:service_type, :name], unique: true
  end
end
```

- [ ] **Step 4: Write the model**

```ruby
# ee/app/models/service_tier.rb
class ServiceTier < ApplicationRecord
  HOURS_PER_MONTH = 730

  validates :name, presence: true
  validates :service_type, presence: true
  validates :price_cents_per_hour, numericality: { greater_than_or_equal_to: 0 }
  validates :name, uniqueness: { scope: :service_type }

  scope :available, -> { where(available: true) }
  scope :for_type, ->(type) { where(service_type: type) }

  def free?
    price_cents_per_hour == 0
  end

  def monthly_price_cents
    (price_cents_per_hour * HOURS_PER_MONTH).round
  end

  def monthly_price_dollars
    monthly_price_cents / 100.0
  end
end
```

- [ ] **Step 5: Run migration and tests**

Run: `bin/rails db:migrate && bin/rails test ee/test/models/service_tier_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add ee/db/migrate/20260322000001_create_service_tiers.rb ee/app/models/service_tier.rb ee/test/models/service_tier_test.rb
git commit -m "feat(ee): add ServiceTier model for database plugin pricing"
```

---

## Task 2: Update DynoTier with Hourly Pricing

**Files:**
- Create: `ee/db/migrate/20260322000002_add_hourly_price_to_dyno_tiers.rb`
- Modify: `ee/app/models/dyno_tier.rb`
- Modify: `ee/test/models/dyno_tier_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# ee/test/models/dyno_tier_test.rb — add these tests
require "test_helper"

class DynoTierTest < ActiveSupport::TestCase
  test "monthly_price_cents calculates from hourly" do
    tier = DynoTier.new(name: "basic", memory_mb: 512, cpu_shares: 50, price_cents_per_month: 300, price_cents_per_hour: 0.4, sleeps: false)
    assert_equal 292, tier.monthly_price_cents  # 0.4 * 730
  end

  test "free? returns true for eco tier" do
    tier = DynoTier.new(price_cents_per_hour: 0, price_cents_per_month: 0, sleeps: true)
    assert tier.free?
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test ee/test/models/dyno_tier_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'monthly_price_cents'`

- [ ] **Step 3: Write the migration**

```ruby
# ee/db/migrate/20260322000002_add_hourly_price_to_dyno_tiers.rb
class AddHourlyPriceToDynoTiers < ActiveRecord::Migration[8.1]
  def change
    add_column :dyno_tiers, :price_cents_per_hour, :decimal, precision: 10, scale: 4, default: 0, null: false
    # Keep price_cents_per_month column for display purposes, make it nullable
    change_column_null :dyno_tiers, :price_cents_per_month, true
  end
end
```

- [ ] **Step 4: Update the model**

Note: Keep `price_cents_per_month` validation but allow it to be derived from hourly rate. The column stays for backward compatibility and as a display hint.

```ruby
# ee/app/models/dyno_tier.rb
class DynoTier < ApplicationRecord
  HOURS_PER_MONTH = 730

  has_many :dyno_allocations

  validates :name, presence: true, uniqueness: true
  validates :memory_mb, :cpu_shares,
    presence: true,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :price_cents_per_hour, numericality: { greater_than_or_equal_to: 0 }
  validates :price_cents_per_month,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :paid, -> { where(sleeps: false) }
  scope :available, -> { all }

  def free?
    price_cents_per_hour == 0
  end

  def monthly_price_cents
    (price_cents_per_hour * HOURS_PER_MONTH).round
  end

  def monthly_price_dollars
    monthly_price_cents / 100.0
  end

  # Keep backward compat
  def price_per_month
    monthly_price_dollars
  end
end
```

- [ ] **Step 5: Run migration and tests**

Run: `bin/rails db:migrate && bin/rails test ee/test/models/dyno_tier_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add ee/db/migrate/20260322000002_add_hourly_price_to_dyno_tiers.rb ee/app/models/dyno_tier.rb ee/test/models/dyno_tier_test.rb
git commit -m "feat(ee): add hourly pricing to DynoTier"
```

---

## Task 3: ResourceUsage Model and Migration

**Files:**
- Create: `ee/db/migrate/20260322000003_create_resource_usages.rb`
- Create: `ee/app/models/resource_usage.rb`
- Create: `ee/test/models/resource_usage_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# ee/test/models/resource_usage_test.rb
require "test_helper"

class ResourceUsageTest < ActiveSupport::TestCase
  test "calculates hours used within period" do
    usage = ResourceUsage.new(
      started_at: Time.parse("2026-03-01 00:00 UTC"),
      stopped_at: Time.parse("2026-03-02 12:00 UTC")
    )
    assert_equal 36.0, usage.hours_in_period(
      Time.parse("2026-03-01 00:00 UTC"),
      Time.parse("2026-03-31 23:59:59 UTC")
    )
  end

  test "clamps to period boundaries" do
    usage = ResourceUsage.new(
      started_at: Time.parse("2026-02-15 00:00 UTC"),  # started before period
      stopped_at: Time.parse("2026-03-15 00:00 UTC")   # stopped mid-period
    )
    hours = usage.hours_in_period(
      Time.parse("2026-03-01 00:00 UTC"),
      Time.parse("2026-03-31 23:59:59 UTC")
    )
    assert_in_delta 336.0, hours, 0.1  # Mar 1 to Mar 15 = 14 days * 24h
  end

  test "still-running resource uses period end as stop" do
    usage = ResourceUsage.new(
      started_at: Time.parse("2026-03-01 00:00 UTC"),
      stopped_at: nil  # still running
    )
    hours = usage.hours_in_period(
      Time.parse("2026-03-01 00:00 UTC"),
      Time.parse("2026-03-31 23:59:59 UTC")
    )
    assert_in_delta 720.0, hours, 0.1  # ~30 days
  end

  test "cost_in_period multiplies hours by rate" do
    usage = ResourceUsage.new(
      started_at: Time.parse("2026-03-01 00:00 UTC"),
      stopped_at: Time.parse("2026-03-02 00:00 UTC"),
      price_cents_per_hour: 0.4
    )
    cost = usage.cost_cents_in_period(
      Time.parse("2026-03-01 00:00 UTC"),
      Time.parse("2026-03-31 23:59:59 UTC")
    )
    assert_in_delta 9.6, cost, 0.01  # 24h * 0.4
  end

  test "active scope returns running resources" do
    # Will test with fixtures
    assert_respond_to ResourceUsage, :active
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test ee/test/models/resource_usage_test.rb`
Expected: FAIL — `NameError: uninitialized constant ResourceUsage`

- [ ] **Step 3: Write the migration**

```ruby
# ee/db/migrate/20260322000003_create_resource_usages.rb
class CreateResourceUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :resource_usages do |t|
      t.references :user, null: false, foreign_key: true
      t.string :resource_type, null: false     # "container", "database"
      t.string :resource_id_ref, null: false   # polymorphic ref as string (e.g. "AppRecord:123" or "DatabaseService:45")
      t.string :tier_name, null: false         # "basic", "standard-1x", etc.
      t.decimal :price_cents_per_hour, precision: 10, scale: 4, null: false, default: 0
      t.datetime :started_at, null: false
      t.datetime :stopped_at                   # nil = still running
      t.jsonb :metadata, default: {}           # { app_name: "my-app", process_type: "web" }
      t.timestamps
    end
    add_index :resource_usages, [:user_id, :stopped_at]
    add_index :resource_usages, [:resource_type, :resource_id_ref]
  end
end
```

- [ ] **Step 4: Write the model**

```ruby
# ee/app/models/resource_usage.rb
class ResourceUsage < ApplicationRecord
  belongs_to :user

  validates :resource_type, :resource_id_ref, :tier_name, :started_at, presence: true
  validates :price_cents_per_hour, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(stopped_at: nil) }
  scope :in_period, ->(start_time, end_time) {
    where("started_at < ? AND (stopped_at IS NULL OR stopped_at > ?)", end_time, start_time)
  }
  scope :billable, -> { where("price_cents_per_hour > 0") }
  scope :for_user, ->(user) { where(user: user) }

  def active?
    stopped_at.nil?
  end

  def stop!(at: Time.current)
    update!(stopped_at: at)
  end

  def hours_in_period(period_start, period_end)
    effective_start = [started_at, period_start].max
    effective_end = [stopped_at || period_end, period_end].min
    return 0.0 if effective_end <= effective_start
    (effective_end - effective_start) / 1.hour
  end

  def cost_cents_in_period(period_start, period_end)
    hours_in_period(period_start, period_end) * price_cents_per_hour
  end
end
```

- [ ] **Step 5: Run migration and tests**

Run: `bin/rails db:migrate && bin/rails test ee/test/models/resource_usage_test.rb`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add ee/db/migrate/20260322000003_create_resource_usages.rb ee/app/models/resource_usage.rb ee/test/models/resource_usage_test.rb
git commit -m "feat(ee): add ResourceUsage model for hourly billing tracking"
```

---

## Task 4: Add Billing Fields to Users

**Files:**
- Create: `ee/db/migrate/20260322000004_add_billing_fields_to_users.rb`
- Modify: `ee/app/models/concerns/ee_user.rb`

- [ ] **Step 1: Write the migration**

```ruby
# ee/db/migrate/20260322000004_add_billing_fields_to_users.rb
class AddBillingFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :stripe_payment_method_id, :string
    add_column :users, :billing_grace_period_ends_at, :datetime
    add_column :users, :billing_status, :integer, default: 0, null: false
    # stripe_customer_id already exists from migration 20260314000005
  end
end
```

- [ ] **Step 2: Update EeUser concern**

```ruby
# ee/app/models/concerns/ee_user.rb
module EeUser
  extend ActiveSupport::Concern

  included do
    has_many :subscriptions, dependent: :destroy
    has_many :invoices, dependent: :destroy
    has_many :usage_events, dependent: :destroy
    has_many :resource_usages, dependent: :destroy

    enum :billing_status, { active: 0, grace_period: 1, suspended: 2 }, prefix: :billing
  end

  def current_plan
    subscriptions.current.includes(:plan).first&.plan || Plan.find_by(name: "free")
  end

  def has_payment_method?
    stripe_payment_method_id.present?
  end

  def active_resource_usages
    resource_usages.active
  end

  def estimated_monthly_cost_cents
    now = Time.current
    period_start = now.beginning_of_month
    period_end = now.end_of_month
    resource_usages.active.billable.sum { |u| u.cost_cents_in_period(period_start, period_end) }
  end

  def free_tier_counts
    active = resource_usages.active
    {
      eco_containers: active.where(resource_type: "container", tier_name: "eco").count,
      mini_databases: active.where(resource_type: "database").where("tier_name LIKE ?", "mini%").count,
      starter_minio: active.where(resource_type: "database", tier_name: "starter").count
    }
  end
end
```

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: SUCCESS

- [ ] **Step 4: Commit**

```bash
git add ee/db/migrate/20260322000004_add_billing_fields_to_users.rb ee/app/models/concerns/ee_user.rb
git commit -m "feat(ee): add billing fields to users and resource usage tracking"
```

---

## Task 5: BillingCalculator Service

**Files:**
- Create: `ee/app/services/billing_calculator.rb`
- Create: `ee/test/services/billing_calculator_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# ee/test/services/billing_calculator_test.rb
require "test_helper"

class BillingCalculatorTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @period_start = Time.parse("2026-03-01 00:00 UTC")
    @period_end = Time.parse("2026-03-31 23:59:59 UTC")
  end

  test "calculates total cost for user in period" do
    # Create a basic container running for 10 days
    ResourceUsage.create!(
      user: @user,
      resource_type: "container",
      resource_id_ref: "AppRecord:1",
      tier_name: "basic",
      price_cents_per_hour: 0.4,
      started_at: @period_start,
      stopped_at: @period_start + 10.days
    )

    calc = BillingCalculator.new(@user, @period_start, @period_end)
    result = calc.calculate

    assert_equal 1, result[:line_items].size
    item = result[:line_items].first
    assert_equal "container", item[:resource_type]
    assert_equal "basic", item[:tier_name]
    assert_in_delta 240.0, item[:hours], 0.1  # 10 days * 24h
    assert_in_delta 96.0, item[:cost_cents], 1.0  # 240h * 0.4
    assert_in_delta result[:total_cents], 96.0, 1.0
  end

  test "skips free resources" do
    ResourceUsage.create!(
      user: @user,
      resource_type: "container",
      resource_id_ref: "AppRecord:1",
      tier_name: "eco",
      price_cents_per_hour: 0,
      started_at: @period_start,
      stopped_at: nil
    )

    calc = BillingCalculator.new(@user, @period_start, @period_end)
    result = calc.calculate

    assert_equal 0, result[:total_cents]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test ee/test/services/billing_calculator_test.rb`
Expected: FAIL — `NameError: uninitialized constant BillingCalculator`

- [ ] **Step 3: Write the service**

```ruby
# ee/app/services/billing_calculator.rb
class BillingCalculator
  def initialize(user, period_start, period_end)
    @user = user
    @period_start = period_start
    @period_end = period_end
  end

  def calculate
    usages = @user.resource_usages
      .in_period(@period_start, @period_end)
      .billable

    line_items = usages.map do |usage|
      hours = usage.hours_in_period(@period_start, @period_end)
      cost_cents = usage.cost_cents_in_period(@period_start, @period_end)

      {
        resource_usage_id: usage.id,
        resource_type: usage.resource_type,
        resource_id_ref: usage.resource_id_ref,
        tier_name: usage.tier_name,
        hours: hours.round(2),
        rate_cents_per_hour: usage.price_cents_per_hour,
        cost_cents: cost_cents.round(2),
        description: build_description(usage, hours),
        metadata: usage.metadata
      }
    end

    total = line_items.sum { |i| i[:cost_cents] }

    {
      user_id: @user.id,
      period_start: @period_start,
      period_end: @period_end,
      line_items: line_items,
      total_cents: total.round,
      total_dollars: (total / 100.0).round(2)
    }
  end

  private

  def build_description(usage, hours)
    name = usage.metadata&.dig("name") || usage.resource_id_ref
    "#{usage.tier_name} #{usage.resource_type} (#{name}) — #{hours.round(1)}h"
  end
end
```

- [ ] **Step 4: Run tests**

Run: `bin/rails test ee/test/services/billing_calculator_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add ee/app/services/billing_calculator.rb ee/test/services/billing_calculator_test.rb
git commit -m "feat(ee): add BillingCalculator service for hourly cost calculation"
```

---

## Task 6: StripeBilling Service

**Files:**
- Create: `ee/app/services/stripe_billing.rb`
- Create: `ee/test/services/stripe_billing_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# ee/test/services/stripe_billing_test.rb
require "test_helper"

class StripeBillingTest < ActiveSupport::TestCase
  test "find_or_create_customer creates new customer" do
    user = users(:one)
    user.update!(stripe_customer_id: nil)

    mock_customer = OpenStruct.new(id: "cus_test123")
    Stripe::Customer.stub(:create, mock_customer) do
      service = StripeBilling.new(user)
      customer = service.find_or_create_customer

      assert_equal "cus_test123", customer.id
      assert_equal "cus_test123", user.reload.stripe_customer_id
    end
  end

  test "find_or_create_customer retrieves existing" do
    user = users(:one)
    user.update!(stripe_customer_id: "cus_existing")

    mock_customer = OpenStruct.new(id: "cus_existing")
    Stripe::Customer.stub(:retrieve, mock_customer) do
      service = StripeBilling.new(user)
      customer = service.find_or_create_customer

      assert_equal "cus_existing", customer.id
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test ee/test/services/stripe_billing_test.rb`
Expected: FAIL — `NameError: uninitialized constant StripeBilling`

- [ ] **Step 3: Write the service**

```ruby
# ee/app/services/stripe_billing.rb
class StripeBilling
  def initialize(user)
    @user = user
  end

  def find_or_create_customer
    if @user.stripe_customer_id.present?
      Stripe::Customer.retrieve(@user.stripe_customer_id)
    else
      customer = Stripe::Customer.create(
        email: @user.email,
        metadata: { wokku_user_id: @user.id }
      )
      @user.update!(stripe_customer_id: customer.id)
      customer
    end
  end

  def create_setup_intent
    customer = find_or_create_customer
    Stripe::SetupIntent.create(
      customer: customer.id,
      payment_method_types: ["card"]
    )
  end

  def save_payment_method(payment_method_id)
    customer = find_or_create_customer
    Stripe::PaymentMethod.attach(payment_method_id, { customer: customer.id })
    Stripe::Customer.update(customer.id, {
      invoice_settings: { default_payment_method: payment_method_id }
    })
    @user.update!(stripe_payment_method_id: payment_method_id)
  end

  def remove_payment_method
    if @user.stripe_payment_method_id.present?
      Stripe::PaymentMethod.detach(@user.stripe_payment_method_id)
      @user.update!(stripe_payment_method_id: nil)
    end
  end

  def create_invoice(line_items:, period_start:, period_end:)
    customer = find_or_create_customer
    return nil if line_items.empty?

    line_items.each do |item|
      Stripe::InvoiceItem.create(
        customer: customer.id,
        amount: item[:cost_cents].round,
        currency: "usd",
        description: item[:description]
      )
    end

    invoice = Stripe::Invoice.create(
      customer: customer.id,
      auto_advance: true,
      collection_method: "charge_automatically",
      metadata: {
        period_start: period_start.iso8601,
        period_end: period_end.iso8601
      }
    )

    Stripe::Invoice.finalize_invoice(invoice.id)

    @user.invoices.create!(
      amount_cents: line_items.sum { |i| i[:cost_cents] }.round,
      status: :pending,
      stripe_invoice_id: invoice.id
    )

    invoice
  end
end
```

- [ ] **Step 4: Run tests**

Run: `bin/rails test ee/test/services/stripe_billing_test.rb`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add ee/app/services/stripe_billing.rb ee/test/services/stripe_billing_test.rb
git commit -m "feat(ee): add StripeBilling service for payment management and invoicing"
```

---

## Task 7: BillingCycleJob

**Files:**
- Create: `ee/app/jobs/billing_cycle_job.rb`
- Create: `ee/test/jobs/billing_cycle_job_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# ee/test/jobs/billing_cycle_job_test.rb
require "test_helper"

class BillingCycleJobTest < ActiveSupport::TestCase
  test "generates invoices for users with billable usage" do
    user = users(:one)
    user.update!(stripe_customer_id: "cus_test", stripe_payment_method_id: "pm_test")

    ResourceUsage.create!(
      user: user,
      resource_type: "container",
      resource_id_ref: "AppRecord:1",
      tier_name: "basic",
      price_cents_per_hour: 0.4,
      started_at: 1.month.ago.beginning_of_month,
      stopped_at: nil
    )

    # Stub all Stripe API calls
    mock_customer = OpenStruct.new(id: "cus_test")
    mock_invoice = OpenStruct.new(id: "inv_test")

    Stripe::Customer.stub(:retrieve, mock_customer) do
      Stripe::InvoiceItem.stub(:create, true) do
        Stripe::Invoice.stub(:create, mock_invoice) do
          Stripe::Invoice.stub(:finalize_invoice, mock_invoice) do
            assert_difference "Invoice.count", 1 do
              BillingCycleJob.perform_now
            end
          end
        end
      end
    end
  end

  test "skips users without payment method" do
    user = users(:one)
    user.update!(stripe_customer_id: "cus_test", stripe_payment_method_id: nil)

    ResourceUsage.create!(
      user: user,
      resource_type: "container",
      resource_id_ref: "AppRecord:1",
      tier_name: "basic",
      price_cents_per_hour: 0.4,
      started_at: 1.month.ago.beginning_of_month,
      stopped_at: nil
    )

    assert_no_difference "Invoice.count" do
      BillingCycleJob.perform_now
    end
  end
end
```

- [ ] **Step 2: Write the job**

```ruby
# ee/app/jobs/billing_cycle_job.rb
class BillingCycleJob < ApplicationJob
  queue_as :billing

  def perform(period_end: 1.day.ago.end_of_day)
    period_start = period_end.beginning_of_month
    period_end = period_end.end_of_month

    User.joins(:resource_usages)
      .where(resource_usages: { price_cents_per_hour: 0.0001.. })
      .where("resource_usages.started_at < ? AND (resource_usages.stopped_at IS NULL OR resource_usages.stopped_at > ?)", period_end, period_start)
      .distinct
      .find_each do |user|
        process_user(user, period_start, period_end)
      rescue => e
        Rails.logger.error("BillingCycleJob: Failed for user #{user.id}: #{e.message}")
      end
  end

  private

  def process_user(user, period_start, period_end)
    return unless user.has_payment_method?

    calc = BillingCalculator.new(user, period_start, period_end)
    result = calc.calculate

    return if result[:total_cents] < 50  # Skip invoices under $0.50

    billing = StripeBilling.new(user)
    billing.create_invoice(
      line_items: result[:line_items],
      period_start: period_start,
      period_end: period_end
    )

    Rails.logger.info("BillingCycleJob: Invoiced user #{user.id} for $#{result[:total_dollars]}")
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add ee/app/jobs/billing_cycle_job.rb ee/test/jobs/billing_cycle_job_test.rb
git commit -m "feat(ee): add BillingCycleJob for monthly invoice generation"
```

---

## Task 8: PaymentFailureJob

**Files:**
- Create: `ee/app/jobs/payment_failure_job.rb`

- [ ] **Step 1: Write the job**

```ruby
# ee/app/jobs/payment_failure_job.rb
class PaymentFailureJob < ApplicationJob
  queue_as :billing

  GRACE_PERIOD = 3.days

  def perform
    handle_new_failures
    handle_expired_grace_periods
  end

  private

  def handle_new_failures
    User.where(billing_status: :active)
      .joins(:invoices)
      .where(invoices: { status: :failed })
      .distinct
      .find_each do |user|
        user.update!(
          billing_status: :grace_period,
          billing_grace_period_ends_at: GRACE_PERIOD.from_now
        )
        Rails.logger.warn("PaymentFailureJob: User #{user.id} entered grace period")
      end
  end

  def handle_expired_grace_periods
    User.where(billing_status: :grace_period)
      .where("billing_grace_period_ends_at < ?", Time.current)
      .find_each do |user|
        suspend_paid_resources(user)
        user.update!(billing_status: :suspended)
        Rails.logger.warn("PaymentFailureJob: Suspended user #{user.id} paid resources")
      end
  end

  def suspend_paid_resources(user)
    user.resource_usages.active.billable.find_each do |usage|
      usage.stop!
      # Stop the actual container/database via Dokku if it's a container
      if usage.resource_type == "container"
        app = AppRecord.find_by(id: usage.resource_id_ref.split(":").last)
        if app
          client = Dokku::Client.new(app.server)
          Dokku::Processes.new(client).stop(app.name)
          app.stopped!
        end
      end
    rescue => e
      Rails.logger.error("PaymentFailureJob: Failed to stop #{usage.resource_id_ref}: #{e.message}")
    end
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add ee/app/jobs/payment_failure_job.rb
git commit -m "feat(ee): add PaymentFailureJob for grace period and resource suspension"
```

---

## Task 9: Usage Tracking Enforcement (PlanEnforceable Rewrite)

**Files:**
- Modify: `ee/app/controllers/concerns/plan_enforceable.rb`
- Modify: `ee/config/initializers/ee.rb`

- [ ] **Step 1: Rewrite PlanEnforceable for per-resource billing**

```ruby
# ee/app/controllers/concerns/plan_enforceable.rb
module PlanEnforceable
  extend ActiveSupport::Concern

  private

  # Check if user can create a paid resource (has payment method)
  def enforce_payment_method!(tier_price_cents_per_hour)
    return if tier_price_cents_per_hour == 0  # Free tier, no card needed

    unless current_user.has_payment_method?
      render json: {
        error: "Payment method required for paid resources",
        action: "add_payment_method",
        url: "/dashboard/billing"
      }, status: :payment_required
    end
  end

  # Check free tier limits
  def enforce_free_container_limit!
    return if current_user.has_payment_method?

    counts = current_user.free_tier_counts
    if counts[:eco_containers] >= 1
      render json: {
        error: "Free tier limited to 1 eco container. Add a payment method for more.",
        url: "/dashboard/billing"
      }, status: :payment_required
    end
  end

  def enforce_free_database_limit!(service_type)
    return if current_user.has_payment_method?

    counts = current_user.free_tier_counts
    if counts[:mini_databases] >= 1
      render json: {
        error: "Free tier limited to 1 mini database. Add a payment method for more.",
        url: "/dashboard/billing"
      }, status: :payment_required
    end
  end

  # Record resource usage when a resource is created
  def track_resource_created(resource_type:, resource_id_ref:, tier_name:, price_cents_per_hour:, metadata: {})
    current_user.resource_usages.create!(
      resource_type: resource_type,
      resource_id_ref: resource_id_ref,
      tier_name: tier_name,
      price_cents_per_hour: price_cents_per_hour,
      started_at: Time.current,
      metadata: metadata
    )
  end

  # Stop tracking when resource is destroyed
  def track_resource_destroyed(resource_type:, resource_id_ref:)
    current_user.resource_usages
      .active
      .where(resource_type: resource_type, resource_id_ref: resource_id_ref)
      .find_each(&:stop!)
  end
end
```

- [ ] **Step 2: Update EE initializer**

```ruby
# ee/config/initializers/ee.rb
Rails.application.config.to_prepare do
  User.include(EeUser)
  AppRecord.include(EeAppRecord)
  Notification.include(EeNotification)

  # Include billing enforcement in API controllers
  Api::V1::AppsController.include(PlanEnforceable)
  Api::V1::AppsController.before_action(:enforce_free_container_limit!, only: [:create])

  Api::V1::DatabasesController.include(PlanEnforceable)
  Api::V1::DatabasesController.before_action(:enforce_free_database_limit!, only: [:create])

  # Include in dashboard controllers too
  Dashboard::AppsController.include(PlanEnforceable)
  Dashboard::AppsController.before_action(:enforce_free_container_limit!, only: [:create])

  Dashboard::DatabasesController.include(PlanEnforceable)
  Dashboard::DatabasesController.before_action(:enforce_free_database_limit!, only: [:create])
end
```

- [ ] **Step 3: Commit**

```bash
git add ee/app/controllers/concerns/plan_enforceable.rb ee/config/initializers/ee.rb
git commit -m "feat(ee): rewrite PlanEnforceable for per-resource billing with free tier limits"
```

---

## Task 10: Stripe Webhook Updates

**Files:**
- Modify: `ee/app/controllers/webhooks/stripe_controller.rb`

Note: This is a full rewrite — the old subscription-based handlers (checkout.session.completed, customer.subscription.updated/deleted) are removed since we no longer use plan-based subscriptions.

- [ ] **Step 1: Update webhook handler for invoice events**

```ruby
# ee/app/controllers/webhooks/stripe_controller.rb
module Webhooks
  class StripeController < ActionController::API
    def create
      payload = request.body.read
      sig_header = request.headers["Stripe-Signature"]

      begin
        event = Stripe::Webhook.construct_event(payload, sig_header, ENV["STRIPE_WEBHOOK_SECRET"])
      rescue JSON::ParserError, Stripe::SignatureVerificationError
        return head :bad_request
      end

      case event.type
      when "invoice.paid"
        handle_invoice_paid(event.data.object)
      when "invoice.payment_failed"
        handle_payment_failed(event.data.object)
      when "payment_method.attached"
        handle_payment_method_attached(event.data.object)
      when "payment_method.detached"
        handle_payment_method_detached(event.data.object)
      end

      head :ok
    end

    private

    def handle_invoice_paid(stripe_invoice)
      invoice = Invoice.find_by(stripe_invoice_id: stripe_invoice.id)
      invoice&.update!(status: :paid, paid_at: Time.current)

      user = User.find_by(stripe_customer_id: stripe_invoice.customer)
      if user&.billing_grace_period?
        user.update!(billing_status: :active, billing_grace_period_ends_at: nil)
      end
    end

    def handle_payment_failed(stripe_invoice)
      invoice = Invoice.find_by(stripe_invoice_id: stripe_invoice.id)
      invoice&.update!(status: :failed)

      user = User.find_by(stripe_customer_id: stripe_invoice.customer)
      PaymentFailureJob.perform_later if user
    end

    def handle_payment_method_attached(payment_method)
      user = User.find_by(stripe_customer_id: payment_method.customer)
      user&.update!(stripe_payment_method_id: payment_method.id, billing_status: :active)
    end

    def handle_payment_method_detached(payment_method)
      user = User.find_by(stripe_payment_method_id: payment_method.id)
      user&.update!(stripe_payment_method_id: nil)
    end
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add ee/app/controllers/webhooks/stripe_controller.rb
git commit -m "feat(ee): update Stripe webhooks for usage-based invoice handling"
```

---

## Task 11: Payment Methods Controller

**Files:**
- Create: `ee/app/controllers/dashboard/payment_methods_controller.rb`
- Modify: `ee/config/routes/ee.rb`

- [ ] **Step 1: Write the controller**

```ruby
# ee/app/controllers/dashboard/payment_methods_controller.rb
module Dashboard
  class PaymentMethodsController < BaseController
    def create
      billing = StripeBilling.new(current_user)
      setup_intent = billing.create_setup_intent

      render json: { client_secret: setup_intent.client_secret }
    end

    def confirm
      billing = StripeBilling.new(current_user)
      billing.save_payment_method(params[:payment_method_id])

      redirect_to dashboard_billing_path, notice: "Payment method added"
    rescue Stripe::InvalidRequestError => e
      redirect_to dashboard_billing_path, alert: e.message
    end

    def destroy
      billing = StripeBilling.new(current_user)
      billing.remove_payment_method

      redirect_to dashboard_billing_path, notice: "Payment method removed"
    rescue Stripe::InvalidRequestError => e
      redirect_to dashboard_billing_path, alert: e.message
    end
  end
end
```

- [ ] **Step 2: Update routes**

```ruby
# ee/config/routes/ee.rb
namespace :dashboard do
  resource :billing, only: [:show], controller: "billing"
  resource :payment_method, only: [:create, :destroy], controller: "payment_methods" do
    post :confirm
  end
end

namespace :api do
  namespace :v1 do
    resource :billing, only: [], controller: "billing" do
      get :current_plan
      get :usage
      post :create_checkout
      post :portal
    end
    resources :apps do
      resources :dynos, only: [:index, :update]
    end
  end
end

post "/webhooks/stripe", to: "webhooks/stripe#create"
```

- [ ] **Step 3: Commit**

```bash
git add ee/app/controllers/dashboard/payment_methods_controller.rb ee/config/routes/ee.rb
git commit -m "feat(ee): add payment method management controller and routes"
```

---

## Task 12: Billing Dashboard View (Rewrite)

**Files:**
- Modify: `ee/app/controllers/dashboard/billing_controller.rb`
- Rewrite: `ee/app/views/dashboard/billing/show.html.erb`
- Create: `ee/app/views/dashboard/billing/_usage_table.html.erb`
- Create: `ee/app/views/dashboard/billing/_payment_method.html.erb`
- Create: `ee/app/views/dashboard/billing/_invoice_history.html.erb`

- [ ] **Step 1: Update billing controller**

```ruby
# ee/app/controllers/dashboard/billing_controller.rb
module Dashboard
  class BillingController < BaseController
    def show
      @active_usages = current_user.resource_usages.active.order(started_at: :desc)
      @period_start = Time.current.beginning_of_month
      @period_end = Time.current.end_of_month

      calc = BillingCalculator.new(current_user, @period_start, @period_end)
      @billing = calc.calculate

      @invoices = current_user.invoices.order(created_at: :desc).limit(12)
      @has_payment_method = current_user.has_payment_method?
      @dyno_tiers = DynoTier.order(:price_cents_per_hour)
    end
  end
end
```

- [ ] **Step 2: Rewrite billing show view**

```erb
<%# ee/app/views/dashboard/billing/show.html.erb %>
<div class="max-w-4xl mx-auto space-y-6">
  <div class="flex items-center justify-between">
    <h1 class="text-2xl font-bold text-white">Billing</h1>
    <% if @billing[:total_cents] > 0 %>
      <div class="text-right">
        <p class="text-xs text-gray-500 uppercase tracking-wider">Estimated this month</p>
        <p class="text-2xl font-bold text-white">$<%= @billing[:total_dollars] %></p>
      </div>
    <% end %>
  </div>

  <%# Payment Method %>
  <%= render "dashboard/billing/payment_method" %>

  <%# Current Usage %>
  <% if @active_usages.any? %>
    <%= render "dashboard/billing/usage_table" %>
  <% else %>
    <div class="bg-[#1E293B]/60 rounded-xl border border-[#334155]/50 p-8 text-center">
      <p class="text-gray-500">No active resources. Create an app or database to get started.</p>
    </div>
  <% end %>

  <%# Invoice History %>
  <% if @invoices.any? %>
    <%= render "dashboard/billing/invoice_history" %>
  <% end %>
</div>
```

- [ ] **Step 3: Write payment method partial**

```erb
<%# ee/app/views/dashboard/billing/_payment_method.html.erb %>
<div class="bg-[#1E293B]/60 rounded-xl border border-[#334155]/50 p-5">
  <h2 class="text-sm font-semibold text-white uppercase tracking-wider mb-3">Payment Method</h2>
  <% if @has_payment_method %>
    <div class="flex items-center justify-between">
      <div class="flex items-center space-x-3">
        <svg class="w-8 h-5 text-gray-400" fill="currentColor" viewBox="0 0 24 24"><path d="M20 4H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V6c0-1.11-.89-2-2-2zm0 14H4v-6h16v6zm0-10H4V6h16v2z"/></svg>
        <span class="text-sm text-gray-300">Card on file</span>
      </div>
      <%= button_to "Remove", dashboard_payment_method_path, method: :delete, class: "text-xs text-red-400 hover:text-red-300 transition", data: { turbo_confirm: "Remove payment method? Paid resources will be stopped." } %>
    </div>
  <% else %>
    <p class="text-sm text-gray-500 mb-3">Add a payment method to use paid containers and databases.</p>
    <a href="#" data-action="click->stripe#setupPayment" class="inline-flex items-center px-4 py-2 bg-green-500 text-[#0B1120] text-sm font-semibold rounded-md hover:bg-green-400 transition">Add Payment Method</a>
  <% end %>
</div>
```

- [ ] **Step 4: Write usage table partial**

```erb
<%# ee/app/views/dashboard/billing/_usage_table.html.erb %>
<div class="bg-[#1E293B]/60 rounded-xl border border-[#334155]/50 overflow-hidden">
  <div class="px-5 py-3 border-b border-[#334155]/50">
    <h2 class="text-sm font-semibold text-white uppercase tracking-wider">Current Usage — <%= @period_start.strftime("%B %Y") %></h2>
  </div>
  <table class="w-full text-sm">
    <thead>
      <tr class="text-xs text-gray-500 uppercase tracking-wider border-b border-[#334155]/30">
        <th class="px-5 py-2 text-left">Resource</th>
        <th class="px-5 py-2 text-left">Tier</th>
        <th class="px-5 py-2 text-right">Hours</th>
        <th class="px-5 py-2 text-right">Rate</th>
        <th class="px-5 py-2 text-right">Cost</th>
      </tr>
    </thead>
    <tbody>
      <% @billing[:line_items].each do |item| %>
        <tr class="border-b border-[#334155]/20 hover:bg-[#1E293B]">
          <td class="px-5 py-3 text-gray-300 font-mono text-xs"><%= item[:metadata]&.dig("name") || item[:resource_id_ref] %></td>
          <td class="px-5 py-3">
            <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-[#334155] text-gray-300">
              <%= item[:tier_name] %> <%= item[:resource_type] %>
            </span>
          </td>
          <td class="px-5 py-3 text-right text-gray-400"><%= item[:hours] %>h</td>
          <td class="px-5 py-3 text-right text-gray-500">$<%= format("%.4f", item[:rate_cents_per_hour] / 100.0) %>/h</td>
          <td class="px-5 py-3 text-right text-white font-medium">$<%= format("%.2f", item[:cost_cents] / 100.0) %></td>
        </tr>
      <% end %>
    </tbody>
    <tfoot>
      <tr class="border-t border-[#334155]">
        <td colspan="4" class="px-5 py-3 text-right text-sm text-gray-400 font-semibold">Estimated Total</td>
        <td class="px-5 py-3 text-right text-white text-lg font-bold">$<%= @billing[:total_dollars] %></td>
      </tr>
    </tfoot>
  </table>
</div>
```

- [ ] **Step 5: Write invoice history partial**

```erb
<%# ee/app/views/dashboard/billing/_invoice_history.html.erb %>
<div class="bg-[#1E293B]/60 rounded-xl border border-[#334155]/50 overflow-hidden">
  <div class="px-5 py-3 border-b border-[#334155]/50">
    <h2 class="text-sm font-semibold text-white uppercase tracking-wider">Invoice History</h2>
  </div>
  <table class="w-full text-sm">
    <thead>
      <tr class="text-xs text-gray-500 uppercase tracking-wider border-b border-[#334155]/30">
        <th class="px-5 py-2 text-left">Date</th>
        <th class="px-5 py-2 text-left">Status</th>
        <th class="px-5 py-2 text-right">Amount</th>
      </tr>
    </thead>
    <tbody>
      <% @invoices.each do |invoice| %>
        <tr class="border-b border-[#334155]/20">
          <td class="px-5 py-3 text-gray-400"><%= invoice.created_at.strftime("%b %d, %Y") %></td>
          <td class="px-5 py-3">
            <% badge_class = case invoice.status
              when "paid" then "bg-green-500/10 text-green-400"
              when "pending" then "bg-yellow-500/10 text-yellow-400"
              when "failed" then "bg-red-500/10 text-red-400"
              else "bg-gray-500/10 text-gray-400"
            end %>
            <span class="inline-flex px-2 py-0.5 rounded text-xs font-medium <%= badge_class %>"><%= invoice.status.capitalize %></span>
          </td>
          <td class="px-5 py-3 text-right text-white">$<%= format("%.2f", invoice.amount_cents / 100.0) %></td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
```

- [ ] **Step 6: Commit**

```bash
git add ee/app/controllers/dashboard/billing_controller.rb ee/app/views/dashboard/billing/
git commit -m "feat(ee): rewrite billing dashboard for per-resource usage-based billing"
```

---

## Task 13: Pricing Page Rewrite (CE)

**Files:**
- Modify: `app/views/pages/pricing.html.erb`
- Modify: `app/controllers/pages_controller.rb`

- [ ] **Step 1: Update pricing controller**

```ruby
# app/controllers/pages_controller.rb — update pricing method
def pricing
  if Wokku.ee? && defined?(DynoTier)
    @dyno_tiers = DynoTier.order(:price_cents_per_hour)
    @service_tiers = ServiceTier.available.order(:service_type, :price_cents_per_hour)
  end
end
```

- [ ] **Step 2: Rewrite pricing page with per-resource pricing and calculator**

Replace `app/views/pages/pricing.html.erb` with a page showing:
- Container pricing table (Eco through Performance)
- Database pricing tables grouped by type
- Interactive cost calculator: user selects containers + databases, shows estimated monthly cost
- Comparison callout vs Heroku pricing
- "60-80% cheaper than Heroku" badge
- Stimulus controller `pricing-calculator` for interactive total

The pricing page should work for both CE (static) and EE (dynamic from DB).

- [ ] **Step 3: Commit**

```bash
git add app/views/pages/pricing.html.erb app/controllers/pages_controller.rb
git commit -m "feat: rewrite pricing page with per-resource pricing and cost calculator"
```

---

## Task 14: Seed Data Update

**Files:**
- Modify: `db/seeds.rb`

- [ ] **Step 1: Update seeds with hourly pricing tiers**

Add to the `if Wokku.ee?` block in `db/seeds.rb`:

```ruby
# Dyno Tiers (with hourly pricing)
DynoTier.find_or_create_by!(name: "eco") { |t| t.memory_mb = 256; t.cpu_shares = 25; t.price_cents_per_month = 0; t.price_cents_per_hour = 0; t.sleeps = true }
DynoTier.find_or_create_by!(name: "basic") { |t| t.memory_mb = 512; t.cpu_shares = 50; t.price_cents_per_month = 300; t.price_cents_per_hour = 0.4; t.sleeps = false }
DynoTier.find_or_create_by!(name: "standard-1x") { |t| t.memory_mb = 1024; t.cpu_shares = 100; t.price_cents_per_month = 1000; t.price_cents_per_hour = 1.4; t.sleeps = false }
DynoTier.find_or_create_by!(name: "standard-2x") { |t| t.memory_mb = 2048; t.cpu_shares = 200; t.price_cents_per_month = 2000; t.price_cents_per_hour = 2.7; t.sleeps = false }
DynoTier.find_or_create_by!(name: "performance") { |t| t.memory_mb = 4096; t.cpu_shares = 400; t.price_cents_per_month = 4000; t.price_cents_per_hour = 5.5; t.sleeps = false }

# Service Tiers — Postgres/MySQL/MariaDB
%w[postgres mysql mariadb].each do |db_type|
  ServiceTier.find_or_create_by!(name: "mini", service_type: db_type) { |t| t.price_cents_per_hour = 0; t.spec = { storage_gb: 1, connections: 20 } }
  ServiceTier.find_or_create_by!(name: "basic", service_type: db_type) { |t| t.price_cents_per_hour = 0.7; t.spec = { storage_gb: 10, connections: 20, backups: "daily" } }
  ServiceTier.find_or_create_by!(name: "standard", service_type: db_type) { |t| t.price_cents_per_hour = 2.7; t.spec = { storage_gb: 50, connections: 120, backups: "daily" } }
  ServiceTier.find_or_create_by!(name: "premium", service_type: db_type) { |t| t.price_cents_per_hour = 10.3; t.spec = { storage_gb: 200, connections: 500, backups: "continuous" } }
end

# Service Tiers — Redis/Memcached
%w[redis memcached].each do |cache_type|
  ServiceTier.find_or_create_by!(name: "mini", service_type: cache_type) { |t| t.price_cents_per_hour = 0; t.spec = { memory_mb: 25 } }
  ServiceTier.find_or_create_by!(name: "basic", service_type: cache_type) { |t| t.price_cents_per_hour = 0.4; t.spec = { memory_mb: 100 } }
  ServiceTier.find_or_create_by!(name: "standard", service_type: cache_type) { |t| t.price_cents_per_hour = 1.1; t.spec = { memory_mb: 256 } }
  ServiceTier.find_or_create_by!(name: "premium", service_type: cache_type) { |t| t.price_cents_per_hour = 3.4; t.spec = { memory_mb: 1024 } }
end

# Service Tiers — Elasticsearch
ServiceTier.find_or_create_by!(name: "basic", service_type: "elasticsearch") { |t| t.price_cents_per_hour = 1.1; t.spec = { memory_mb: 512, storage_gb: 5 } }
ServiceTier.find_or_create_by!(name: "standard", service_type: "elasticsearch") { |t| t.price_cents_per_hour = 2.7; t.spec = { memory_mb: 1024, storage_gb: 20 } }

# Service Tiers — MinIO
ServiceTier.find_or_create_by!(name: "starter", service_type: "minio") { |t| t.price_cents_per_hour = 0; t.spec = { storage_gb: 5 } }
ServiceTier.find_or_create_by!(name: "basic", service_type: "minio") { |t| t.price_cents_per_hour = 0.7; t.spec = { storage_gb: 50 } }
ServiceTier.find_or_create_by!(name: "standard", service_type: "minio") { |t| t.price_cents_per_hour = 2.7; t.spec = { storage_gb: 500 } }

# Service Tiers — MongoDB/RabbitMQ
%w[mongodb rabbitmq].each do |type|
  ServiceTier.find_or_create_by!(name: "mini", service_type: type) { |t| t.price_cents_per_hour = 0; t.spec = { memory_mb: 64 } }
  ServiceTier.find_or_create_by!(name: "basic", service_type: type) { |t| t.price_cents_per_hour = 0.7; t.spec = { memory_mb: 256 } }
  ServiceTier.find_or_create_by!(name: "standard", service_type: type) { |t| t.price_cents_per_hour = 2.1; t.spec = { memory_mb: 1024 } }
end

puts "Created service tiers for all database types"
```

- [ ] **Step 2: Commit**

```bash
git add db/seeds.rb
git commit -m "feat: update seeds with hourly pricing for all dyno and service tiers"
```

---

## Task 15: Recurring Job Configuration

**Files:**
- Modify: `config/recurring.yml` (CE — job runs only if class exists)
- Create: `ee/config/recurring_ee.yml` (reference only — loaded via initializer)

- [ ] **Step 1: Add billing jobs to recurring schedule**

Add to `ee/config/initializers/ee.rb` at the end of the `to_prepare` block:

```ruby
# Register EE recurring jobs
Rails.application.config.after_initialize do
  if defined?(SolidQueue) && Rails.env.production?
    # BillingCycleJob runs on the 1st of each month at 2am UTC
    # PaymentFailureJob runs daily at 6am UTC
    # These are registered via the recurring.yml in CE, gated by class existence
  end
end
```

Add to `config/recurring.yml` under the `production:` key (alongside existing entries):

```yaml
  billing_cycle:
    class: BillingCycleJob
    schedule: every month on the 1st at 2am
    queue: billing

  payment_failure_check:
    class: PaymentFailureJob
    schedule: every day at 6am
    queue: billing
```

Note: These are nested under the existing `production:` key. Solid Queue raises `NameError` if the class doesn't exist, so wrap in `if defined?(BillingCycleJob)` in the EE initializer to conditionally register, or gate via a separate `ee/config/recurring_ee.yml` loaded only when EE is present. The simplest approach: keep them in the main file and ensure the EE autoload paths are loaded before Solid Queue starts (already the case via `config/application.rb`).

- [ ] **Step 2: Commit**

```bash
git add config/recurring.yml
git commit -m "feat: add billing cycle and payment failure recurring jobs"
```

---

## Task 16: Data Migration for Existing Users

**Files:**
- Create: `ee/db/migrate/20260322000005_migrate_billing_to_usage_based.rb`

This migration handles the transition from plan-based subscriptions to usage-based billing:
- Creates ResourceUsage records for all currently running containers and databases
- Sets all existing users to `billing_active` status
- Cancels any existing Stripe subscriptions (if live Stripe keys configured)

- [ ] **Step 1: Write the migration**

```ruby
# ee/db/migrate/20260322000005_migrate_billing_to_usage_based.rb
class MigrateBillingToUsageBased < ActiveRecord::Migration[8.1]
  def up
    # Create ResourceUsage records for running apps (eco tier, free)
    execute <<-SQL
      INSERT INTO resource_usages (user_id, resource_type, resource_id_ref, tier_name, price_cents_per_hour, started_at, metadata, created_at, updated_at)
      SELECT ar.created_by_id, 'container', 'AppRecord:' || ar.id, 'eco', 0,
             ar.created_at, json_build_object('name', ar.name), NOW(), NOW()
      FROM app_records ar
      WHERE ar.status IN (0, 3, 4)
      AND NOT EXISTS (
        SELECT 1 FROM resource_usages ru
        WHERE ru.resource_id_ref = 'AppRecord:' || ar.id AND ru.stopped_at IS NULL
      )
    SQL

    # Create ResourceUsage records for running databases (mini tier, free)
    execute <<-SQL
      INSERT INTO resource_usages (user_id, resource_type, resource_id_ref, tier_name, price_cents_per_hour, started_at, metadata, created_at, updated_at)
      SELECT t.owner_id, 'database', 'DatabaseService:' || ds.id, 'mini', 0,
             ds.created_at, json_build_object('name', ds.name, 'service_type', ds.service_type), NOW(), NOW()
      FROM database_services ds
      JOIN servers s ON ds.server_id = s.id
      JOIN teams t ON s.team_id = t.id
      WHERE ds.status = 0
      AND NOT EXISTS (
        SELECT 1 FROM resource_usages ru
        WHERE ru.resource_id_ref = 'DatabaseService:' || ds.id AND ru.stopped_at IS NULL
      )
    SQL

    # Mark all active subscriptions as canceled
    Subscription.where(status: [:active, :trialing]).update_all(status: 2) if table_exists?(:subscriptions)
  end

  def down
    ResourceUsage.delete_all
  end
end
```

- [ ] **Step 2: Run migration**

Run: `bin/rails db:migrate`
Expected: SUCCESS — existing resources now tracked in resource_usages

- [ ] **Step 3: Commit**

```bash
git add ee/db/migrate/20260322000005_migrate_billing_to_usage_based.rb
git commit -m "feat(ee): data migration from plan-based to usage-based billing"
```

---

## Summary

| Task | Component | New Files | Modified Files |
|---|---|---|---|
| 1 | ServiceTier model | 3 | 0 |
| 2 | DynoTier hourly pricing | 1 | 2 |
| 3 | ResourceUsage model | 3 | 0 |
| 4 | User billing fields | 1 | 1 |
| 5 | BillingCalculator | 2 | 0 |
| 6 | StripeBilling service | 2 | 0 |
| 7 | BillingCycleJob | 2 | 0 |
| 8 | PaymentFailureJob | 1 | 0 |
| 9 | PlanEnforceable rewrite | 0 | 2 |
| 10 | Stripe webhooks | 0 | 1 |
| 11 | Payment methods controller | 1 | 1 |
| 12 | Billing dashboard views | 0 | 5 |
| 13 | Pricing page rewrite | 0 | 2 |
| 14 | Seed data | 0 | 1 |
| 15 | Recurring jobs | 0 | 1 |
| 16 | Data migration | 1 | 0 |

**Total: 17 new files, 16 modified files, 16 tasks**
