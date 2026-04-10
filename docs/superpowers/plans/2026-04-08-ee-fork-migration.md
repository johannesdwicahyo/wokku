# CE/EE Fork Migration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure from "CE + ee/ directory" to "CE upstream + EE fork" model. EE (renamed to `wokku.dev`) becomes a complete fork of CE with enterprise features added directly. Deploy wokku.dev from the EE fork.

**Architecture:** CE is the public upstream repo. EE is a private fork that merges from CE. EE-only code (billing, tiers, mobile, AI) lives directly in normal Rails directories in the EE fork — no `ee/` subdirectory, no conditional loading, no concern injection.

**Tech Stack:** Git (fork + upstream remote), GitHub (repo rename), Kamal (deploy from EE fork)

---

## Overview

### Before (current)

```
wokku (CE, public)
├── app/                    ← core features
├── ee/                     ← separate git repo cloned here
│   ├── app/models/         ← EE models (injected via concerns)
│   ├── app/controllers/    ← EE controllers (autoloaded)
│   ├── config/initializers/ee.rb  ← concern injection
│   └── db/migrate/         ← EE migrations
├── config/application.rb   ← conditional ee/ autoloading
├── lib/wokku.rb            ← Wokku.ee? flag
└── Dockerfile              ← clones EE repo at build time with token
```

### After (target)

```
wokku (CE, public)              wokku.dev (EE, private fork)
├── app/                        ├── app/
│   ├── models/                 │   ├── models/
│   │   └── user.rb             │   │   ├── user.rb          (merged with EE fields)
│   │                           │   │   ├── subscription.rb   (EE only)
│   │                           │   │   ├── invoice.rb        (EE only)
│   │                           │   │   └── ...
│   ├── controllers/            │   ├── controllers/
│   │   └── dashboard/          │   │   └── dashboard/
│   │       └── apps_ctrl.rb    │   │       ├── apps_ctrl.rb  (from CE)
│   │                           │   │       ├── billing_ctrl.rb (EE only)
│   │                           │   │       └── ...
│   └── views/                  │   └── views/
│                               │       └── dashboard/billing/ (EE only)
├── docs/content/               ├── docs/content/
│   ├── apps/                   │   ├── apps/          (from CE)
│   └── (no billing/mobile)     │   ├── billing/       (EE only)
│                               │   ├── mobile/        (EE only)
│                               │   └── scaling/tiers.md (EE version)
├── config/                     ├── config/
│   └── deploy.yml (no EE)      │   └── deploy.yml (wokku.dev, simple)
└── Dockerfile (simple)         └── Dockerfile (simple, no token)
```

---

## Task 1: Rename EE Repo on GitHub

- [ ] **Step 1: Rename the repo**

```bash
gh repo rename wokku.dev --repo johannesdwicahyo/wokku-ee --yes
```

- [ ] **Step 2: Verify rename**

```bash
gh repo view johannesdwicahyo/wokku.dev --json name,url
```

Expected: `{"name":"wokku.dev","url":"https://github.com/johannesdwicahyo/wokku.dev"}`

- [ ] **Step 3: Update the local EE remote**

```bash
cd /Users/johannesdwicahyo/Projects/2026/herodokku/ee
git remote set-url origin https://github.com/johannesdwicahyo/wokku.dev.git
```

---

## Task 2: Create EE Fork from CE

This creates a fresh private repo that starts as an exact copy of CE, then we'll add EE code on top.

- [ ] **Step 1: Clone CE into a new working directory**

```bash
cd /Users/johannesdwicahyo/Projects/2026
git clone https://github.com/johannesdwicahyo/wokku.git wokku.dev
cd wokku.dev
```

- [ ] **Step 2: Change remote to point to EE repo**

```bash
git remote set-url origin https://github.com/johannesdwicahyo/wokku.dev.git
git remote add upstream https://github.com/johannesdwicahyo/wokku.git
```

- [ ] **Step 3: Force push CE code as the new base for EE**

```bash
git push origin main --force
```

This replaces the old EE repo content with CE as the base. The old EE code is preserved in the old ee/ directory locally.

- [ ] **Step 4: Verify upstream tracking works**

```bash
git fetch upstream
git log --oneline upstream/main -3
```

---

## Task 3: Merge EE Code into Normal Rails Directories

Working in `/Users/johannesdwicahyo/Projects/2026/wokku.dev`.

The old EE code lives at `/Users/johannesdwicahyo/Projects/2026/herodokku/ee/`.

- [ ] **Step 1: Copy EE models (remove concern pattern, make them standalone)**

```bash
# Copy EE-only models directly
cp ../herodokku/ee/app/models/invoice.rb app/models/
cp ../herodokku/ee/app/models/subscription.rb app/models/
cp ../herodokku/ee/app/models/plan.rb app/models/
cp ../herodokku/ee/app/models/dyno_tier.rb app/models/
cp ../herodokku/ee/app/models/dyno_allocation.rb app/models/
cp ../herodokku/ee/app/models/service_tier.rb app/models/
cp ../herodokku/ee/app/models/usage_event.rb app/models/
cp ../herodokku/ee/app/models/resource_usage.rb app/models/
cp ../herodokku/ee/app/models/oss_revenue_share.rb app/models/
```

- [ ] **Step 2: Merge EE concerns into CE models**

For each concern (ee_user.rb, ee_app_record.rb, ee_notification.rb), merge the code directly into the CE model. For example, for User:

Read `../herodokku/ee/app/models/concerns/ee_user.rb` and add the associations/methods directly into `app/models/user.rb`:

```ruby
# In app/models/user.rb, add:
has_many :subscriptions
has_many :invoices
has_many :usage_events
# ... plus any methods from the concern
```

Do the same for AppRecord and Notification.

- [ ] **Step 3: Copy EE controllers**

```bash
cp ../herodokku/ee/app/controllers/dashboard/billing_controller.rb app/controllers/dashboard/
cp ../herodokku/ee/app/controllers/dashboard/payment_methods_controller.rb app/controllers/dashboard/
cp ../herodokku/ee/app/controllers/dashboard/ai_controller.rb app/controllers/dashboard/
cp ../herodokku/ee/app/controllers/api/v1/billing_controller.rb app/controllers/api/v1/
cp ../herodokku/ee/app/controllers/api/v1/dynos_controller.rb app/controllers/api/v1/
cp ../herodokku/ee/app/controllers/api/v1/ai_controller.rb app/controllers/api/v1/
cp ../herodokku/ee/app/controllers/webhooks/stripe_controller.rb app/controllers/webhooks/
cp ../herodokku/ee/app/controllers/webhooks/ipaymu_controller.rb app/controllers/webhooks/
```

- [ ] **Step 4: Merge PlanEnforceable and ManagedUser concerns**

```bash
cp ../herodokku/ee/app/controllers/concerns/plan_enforceable.rb app/controllers/concerns/
cp ../herodokku/ee/app/controllers/concerns/managed_user.rb app/controllers/concerns/
```

Add the `include` and `before_action` lines from `ee/config/initializers/ee.rb` directly into the relevant controllers (AppsController, DatabasesController, etc.).

- [ ] **Step 5: Copy EE views**

```bash
cp -r ../herodokku/ee/app/views/dashboard/billing app/views/dashboard/
cp -r ../herodokku/ee/app/views/dashboard/ai app/views/dashboard/
cp ../herodokku/ee/app/views/dashboard/shared/_ee_sidebar_items.html.erb app/views/dashboard/shared/
```

- [ ] **Step 6: Copy EE services**

```bash
cp ../herodokku/ee/app/services/billing_calculator.rb app/services/
cp ../herodokku/ee/app/services/ai_debugger.rb app/services/
cp ../herodokku/ee/app/services/ipaymu_client.rb app/services/
cp ../herodokku/ee/app/services/server_placement.rb app/services/
```

- [ ] **Step 7: Copy EE jobs**

```bash
cp ../herodokku/ee/app/jobs/billing_cycle_job.rb app/jobs/
cp ../herodokku/ee/app/jobs/payment_failure_job.rb app/jobs/
cp ../herodokku/ee/app/jobs/monthly_billing_job.rb app/jobs/
cp ../herodokku/ee/app/jobs/billing_grace_check_job.rb app/jobs/
cp ../herodokku/ee/app/jobs/idle_check_job.rb app/jobs/
cp ../herodokku/ee/app/jobs/apply_dyno_tier_job.rb app/jobs/
cp ../herodokku/ee/app/jobs/wake_app_job.rb app/jobs/
```

- [ ] **Step 8: Copy EE migrations**

```bash
cp ../herodokku/ee/db/migrate/*.rb db/migrate/
```

- [ ] **Step 9: Copy EE tests**

```bash
cp ../herodokku/ee/test/models/*.rb test/models/
cp ../herodokku/ee/test/jobs/*.rb test/jobs/
cp -r ../herodokku/ee/test/controllers/ test/controllers/  # merge into existing
cp -r ../herodokku/ee/test/services/ test/services/
```

---

## Task 4: Merge EE Routes and Config

- [ ] **Step 1: Add EE routes directly to routes.rb**

Append the content of `ee/config/routes/ee.rb` into `config/routes.rb`, before the EE route loading line. Then remove the conditional EE route loading:

Remove from routes.rb:
```ruby
ee_routes = Rails.root.join("ee/config/routes/ee.rb")
instance_eval(File.read(ee_routes)) if ee_routes.exist?
```

Add directly:
```ruby
# Enterprise features
namespace :dashboard do
  resource :billing, only: [:show], controller: "billing" do
    post :pay
  end
  resource :payment_method, only: [:create, :destroy], controller: "payment_methods" do
    post :confirm
  end
  post "ai/diagnose", to: "ai#diagnose", as: :ai_diagnose
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
    post "ai/diagnose", to: "ai#diagnose"
  end
end

post "/webhooks/stripe", to: "webhooks/stripe#create"
post "/webhooks/ipaymu", to: "webhooks/ipaymu#create"
```

- [ ] **Step 2: Merge EE gems into Gemfile**

Add to Gemfile (remove the `eval_gemfile` line):

```ruby
# Billing
gem "pay", "~> 7.0"
gem "stripe", "~> 12.0"
```

Remove:
```ruby
eval_gemfile "ee/Gemfile.ee" if File.exist?(File.expand_path("ee/Gemfile.ee", __dir__))
```

Run `bundle install`.

- [ ] **Step 3: Copy EE initializers and merge**

Copy `ee/config/initializers/stripe.rb` to `config/initializers/stripe.rb`.

For `ee/config/initializers/ee.rb`, the concern injection lines are no longer needed (code is merged directly). Move the Solid Queue recurring job registration to a new initializer:

Create `config/initializers/billing_jobs.rb`:
```ruby
Rails.application.config.after_initialize do
  if defined?(SolidQueue) && SolidQueue.respond_to?(:recurring_schedule=)
    recurring = (SolidQueue.recurring_schedule || {}).dup
    recurring["billing_cycle"] = {
      "class" => "BillingCycleJob",
      "schedule" => "every month on the 1st at 2am",
      "queue" => "billing"
    }
    recurring["payment_failure_check"] = {
      "class" => "PaymentFailureJob",
      "schedule" => "every day at 6am",
      "queue" => "billing"
    }
    SolidQueue.recurring_schedule = recurring
  end
end
```

- [ ] **Step 4: Remove ee/ conditional loading from config/application.rb**

Remove the entire `if File.directory?(Rails.root.join("ee"))` block from `config/application.rb`. The EE code now lives in normal directories and is autoloaded naturally.

- [ ] **Step 5: Remove Wokku.ee? from lib/wokku.rb**

Either remove the method entirely or make it always return true:

```ruby
module Wokku
  def self.ee?
    true
  end
end
```

- [ ] **Step 6: Remove ee_helper.rb**

The `ee_feature` helper is no longer needed. Replace any `ee_feature("partial")` calls in views with direct `render("partial")` calls.

---

## Task 5: Simplify Dockerfile and Deploy Config

- [ ] **Step 1: Simplify Dockerfile**

Remove the EE clone block entirely:

```dockerfile
# DELETE these lines:
# Enterprise Edition: clone into /tmp/ee if token is provided
RUN --mount=type=secret,id=WOKKU_EE_TOKEN \
    WOKKU_EE_TOKEN=$(cat /run/secrets/WOKKU_EE_TOKEN 2>/dev/null) && \
    if [ -n "$WOKKU_EE_TOKEN" ]; then \
    git clone https://${WOKKU_EE_TOKEN}@github.com/johannesdwicahyo/wokku-ee.git /tmp/ee && \
    rm -rf /tmp/ee/.git; \
    fi

# DELETE:
RUN mkdir -p ee && if [ -d /tmp/ee ]; then cp /tmp/ee/Gemfile.ee ee/Gemfile.ee; fi

# DELETE:
RUN if [ -d /tmp/ee ]; then rm -rf ee && cp -r /tmp/ee ee; fi
```

The Dockerfile becomes a normal Rails Dockerfile — no secrets, no conditional cloning.

- [ ] **Step 2: Simplify deploy.yml**

Remove the `builder.secrets` block:

```yaml
builder:
  remote: ssh://deploy@43.159.57.11
  arch: amd64
  # No secrets needed — EE code is in the repo directly
```

- [ ] **Step 3: Update .kamal/secrets**

Remove `WOKKU_EE_TOKEN` — no longer needed.

---

## Task 6: Move EE-only Docs Content

- [ ] **Step 1: Keep EE-only docs in the EE fork only**

The following docs pages should only exist in the EE fork (wokku.dev), not in CE:

- `docs/content/billing/plans.md` — references pricing tiers
- `docs/content/billing/usage.md` — references billing
- `docs/content/mobile/download.md` — mobile is EE only
- `docs/content/mobile/notifications.md` — push notifications
- `docs/content/scaling/tiers.md` — dyno tiers (EE only)

In CE, replace these with simple pages that say:

```markdown
# Plans & Pricing

Available on [wokku.dev](https://wokku.dev). Self-hosted CE is free.
```

- [ ] **Step 2: Update sidebar.yml for CE**

Remove or simplify the Billing and Mobile sections in CE's `docs/sidebar.yml`. Keep them full in EE's version.

---

## Task 7: Clean Up CE Repo

Working in `/Users/johannesdwicahyo/Projects/2026/herodokku` (CE).

- [ ] **Step 1: Remove ee/ references from CE**

In CE, the `ee/` directory pattern should remain as-is for self-hosted users who might want to add their own extensions, but the Wokku EE-specific code is gone.

Files to simplify:
- `config/application.rb` — keep the conditional ee/ loading (it's a nice extension mechanism) but it's no longer required for Wokku EE
- `Gemfile` — keep the `eval_gemfile` line (same reason)
- `lib/wokku.rb` — keep `Wokku.ee?` (works as a hook for extensions)
- `Dockerfile` — remove the EE clone block (already done in Task 5, but do it in CE too)

- [ ] **Step 2: Remove EE-only references from CE docs**

Replace billing/mobile/tiers docs with CE-appropriate versions (see Task 6).

- [ ] **Step 3: Commit and push CE**

```bash
git add -A
git commit -m "chore: clean up CE for fork-based EE model"
git push origin main
```

---

## Task 8: Test the EE Fork

Working in `/Users/johannesdwicahyo/Projects/2026/wokku.dev`.

- [ ] **Step 1: Run migrations**

```bash
bin/rails db:migrate
```

- [ ] **Step 2: Run tests**

```bash
bin/rails test
```

- [ ] **Step 3: Boot the app locally**

```bash
bin/dev
```

Verify billing page, AI features, dyno tiers all work.

- [ ] **Step 4: Deploy to wokku.dev**

Update `config/deploy.yml` to point to the new repo:

```yaml
image: johannesdwicahyo/wokku
```

```bash
kamal deploy
```

- [ ] **Step 5: Verify wokku.dev is working**

```bash
curl -s -o /dev/null -w "%{http_code}" https://wokku.dev/up
curl -s -o /dev/null -w "%{http_code}" https://wokku.dev/docs
```

---

## Task 9: Set Up Sync Workflow

- [ ] **Step 1: Document the sync process**

Create `CONTRIBUTING.md` in wokku.dev repo:

```markdown
# Syncing from CE

This repo is a private fork of [wokku](https://github.com/johannesdwicahyo/wokku) (CE).

## Pull CE updates

```bash
git fetch upstream
git merge upstream/main
# Resolve any conflicts
git push origin main
```

## Contributing CE features

Features that should be open-source go to CE first:
1. Make changes in CE repo
2. Push to CE
3. Merge upstream into EE (this repo)
```

- [ ] **Step 2: Commit everything in EE fork**

```bash
git add -A
git commit -m "feat: merge EE features directly into Rails app structure

Migrated from ee/ subdirectory injection pattern to direct fork model.
EE code now lives in normal Rails directories — no conditional loading,
no concern injection, no Dockerfile token dance.

Includes: billing, subscriptions, dyno tiers, service tiers, AI debugger,
iPaymu/Stripe webhooks, plan enforcement, server placement, mobile push.
"
git push origin main
```

---

## Summary

| Step | What | Risk |
|------|------|------|
| 1 | Rename repo | Low — GitHub redirects old URL |
| 2 | Create fork from CE | Low — clean start |
| 3 | Copy EE code to normal dirs | Medium — concern merging needs care |
| 4 | Merge routes/config/gems | Medium — needs testing |
| 5 | Simplify Dockerfile | Low — just deleting lines |
| 6 | Fix docs per edition | Low — content changes |
| 7 | Clean up CE | Low — removing dead code |
| 8 | Test & deploy | High — production deploy |
| 9 | Document sync workflow | Low — just docs |

**Estimated effort:** 2-3 hours for the migration, mostly in Tasks 3-4 (merging code).

**Rollback:** If anything breaks, redeploy from the old EE repo (GitHub preserves the old content under the new name for a period).
