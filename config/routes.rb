# OSS-trimmed routes for the public wokku repo.
#
# This file is the source of truth for the open-source Wokku web UI.
# bin/sync-oss (release mode) overwrites the staged config/routes.rb
# with this version, so any marketing / billing / paid-ad / docs
# routes from wokku-cloud get dropped automatically on release.
#
# Keep this minimal: devise + dashboard namespace + admin namespace +
# webhook receivers used by the OSS-installable GitHub App.

Rails.application.routes.draw do
  devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" }
  # Registrations are OAuth-only — redirect any lingering /users/sign_up
  # links to the sign-in page so they don't 404.
  get "/users/sign_up", to: redirect("/users/sign_in")

  # GitHub OAuth + git webhooks (self-hosters who connect a GitHub App)
  get "/github/callback", to: "github/callbacks#create", as: :github_callback
  post "/webhooks/github", to: "webhooks/github#create"
  post "/webhooks/gitlab", to: "webhooks/gitlab#create"
  post "/webhooks/bitbucket", to: "webhooks/bitbucket#create"

  namespace :dashboard do
    get "/", to: redirect("/dashboard/apps"), as: :root
    get "/deploy",       to: redirect("/dashboard/apps/new")
    get "/addons",       to: redirect("/dashboard/apps")
    resources :templates, only: [ :index, :show, :create ]
    patch "onboarding/skip", to: "onboarding#skip", as: :onboarding_skip
    resources :deploys, only: [ :index ]
    resources :apps do
      collection do
        get :check_name
        get :search
      end
      member do
        post :restart
        post :stop
        post :start
        post :toggle_https
        post :toggle_maintenance
        post :toggle_cdn
        get  :transfer
        post :transfer
        post :backup_now
        post :unlock
        get :runtime_metrics_frame
        get :live_logs_frame
        get :resource_limits_frame
      end
      # Bundle v2 — dedicated upgrade actions (dormant under BUNDLE_V2_ENABLED=false)
      post "addons/postgres/upgrade",
           to: "apps/addons#upgrade_to_dedicated",
           as: :upgrade_to_dedicated_postgres_addon,
           on: :member
      post "addons/redis/upgrade",
           to: "apps/addons#upgrade_redis_to_dedicated",
           as: :upgrade_to_dedicated_redis_addon,
           on: :member
      resources :config, only: [ :index, :create, :update, :destroy ], controller: "config"
      resources :domains, only: [ :index, :create, :destroy ], controller: "domains" do
        member do
          post :ssl
        end
      end
      resources :releases, only: [ :index ], controller: "releases" do
        collection do
          post :deploy
        end
        member do
          post :rollback
        end
      end
      resources :deploys, only: [ :show ], controller: "deploys"
      resource :logs, only: [ :show ], controller: "logs"
      resources :log_drains, only: [ :index, :create, :destroy ], controller: "log_drains"
      resource :metrics, only: [ :show ], controller: "metrics"
      resource :monitor, only: [ :show ], module: "apps", controller: "monitor"
      resource :resources, only: [ :show, :create, :destroy ], controller: "resources"
      resource :scaling, only: [ :show, :update ], controller: "scaling" do
        post :change_tier
      end
      resource :checks, only: [ :show, :update ], controller: "checks"
      resource :terminal, only: [ :show ], controller: "terminals"
      resource :preview_settings, only: %i[update]
      resources :previews, only: %i[index destroy], controller: "preview_management"
      resources :scheduled_tasks, only: %i[index new create destroy]
      get "github/repos", to: "github#repos", as: :github_repos
      post "github/connect", to: "github#connect", as: :github_connect
      delete "github/disconnect", to: "github#disconnect", as: :github_disconnect
    end
    resources :addons, controller: "databases" do
      member do
        post :link
        post :unlink
        post :change_tier
        post :retry
      end
      resource :monitor, only: [ :show ], module: "databases", controller: "monitor"
      resources :backups, only: [ :index, :create ], controller: "backups" do
        member do
          get :download
          post :restore
        end
      end
    end
    get "/resources",        to: redirect("/dashboard/apps")
    get "/resources/*path",  to: redirect("/dashboard/apps")
    get "/cloud_credentials(/*path)", to: redirect("/admin/cloud_credentials")
    get "/teams(/*path)", to: redirect("/dashboard/workspaces"), as: :teams
    resources :notifications, only: [ :index, :create, :destroy ] do
      member do
        post :test
      end
    end
    resources :activities, only: [ :index ]
    resources :app_transfers, only: [ :index, :show, :destroy ] do
      member do
        post :accept
        post :decline
      end
    end
    resource :profile, only: [ :show, :edit, :update ], controller: "profile"
    resource :account_deletion, only: [ :show, :create, :destroy ], controller: "account_deletions"
    resources :api_tokens, only: [ :create, :destroy ]
    resource :device, only: [ :show ], controller: "devices" do
      post :authorize
    end
    resources :ssh_keys, only: [ :create, :destroy ]
    resource :two_factor, only: [ :show ], controller: "two_factor" do
      post :enable
      delete :disable
    end
    post "locale", to: "locales#update", as: :locale

    resources :workspaces, only: %i[index new create show] do
      member { post :switch }
      resources :members, only: %i[create update destroy],
                          controller: "team_members", as: :team_members
    end
  end

  # Admin-only namespace — gated by Devise authenticate block so non-admins
  # get a 401 from Devise before hitting any controller action.
  authenticate :user, ->(u) { u.admin? } do
    namespace :admin do
      root to: "dashboard#index"
      resources :servers do
        collection do
          post :provision
        end
        member do
          post :sync
        end
        resource :terminal, only: [ :show ], controller: "/dashboard/terminals"
        resource :backup_destination, only: [ :edit, :update ], controller: "/dashboard/backup_destinations"
      end
      resources :users, only: [ :index, :show, :destroy ]
      resources :cloud_credentials, only: [ :index, :create, :destroy ]
    end
  end

  # Clean URL shortcuts
  get "/apps", to: redirect("/dashboard/apps")
  get "/apps/*path", to: redirect("/dashboard/apps/%{path}")
  get "/servers", to: redirect("/admin/servers")
  get "/activity", to: redirect("/dashboard/activities")

  # Locale switching (public, no auth required)
  post "/locale", to: "locales#update", as: :public_locale

  # Stub marketing routes — point at PagesController stub. Sign-in view
  # references terms_path + privacy_path, so the helpers must exist.
  get "/terms",     to: "pages#terms",     as: :terms
  get "/privacy",   to: "pages#privacy",   as: :privacy
  get "/faq",       to: "pages#faq",       as: :faq
  get "/changelog", to: "pages#changelog", as: :changelog

  # Stub managed-cloud route helpers. Dashboard views/components reference
  # billing/invoices/usage/payment_method/plan/referrals route helpers —
  # all stripped. We keep the helpers alive (so url_for / link_to don't
  # NoMethodError) by pointing them at /cloud_only_controller (top-level
  # — must NOT be namespaced under Dashboard::, the controller lives at
  # app/controllers/cloud_only_controller.rb).
  get "/dashboard/billing",         to: "cloud_only#show", as: :dashboard_billing,         defaults: { feature: "billing" }
  get "/dashboard/billing/plans",   to: "cloud_only#show", as: :dashboard_billing_plans,   defaults: { feature: "plans" }
  get "/dashboard/invoices",        to: "cloud_only#show", as: :dashboard_invoices,        defaults: { feature: "invoices" }
  get "/dashboard/invoices/:id",    to: "cloud_only#show", as: :dashboard_invoice,         defaults: { feature: "invoices" }
  get "/dashboard/payment_method",  to: "cloud_only#show", as: :dashboard_payment_method,  defaults: { feature: "payment method" }
  get "/dashboard/plan",            to: "cloud_only#show", as: :dashboard_plan,            defaults: { feature: "plan" }
  get "/dashboard/usage",           to: "cloud_only#show", as: :dashboard_usage,           defaults: { feature: "usage" }
  get "/dashboard/referrals",       to: "cloud_only#show", as: :dashboard_referrals,       defaults: { feature: "referrals" }
  get "/admin/promo_codes",         to: "cloud_only#show", as: :admin_promo_codes,         defaults: { feature: "promo codes" }
  get "/admin/promo_codes/new",     to: "cloud_only#show", as: :new_admin_promo_code,      defaults: { feature: "promo codes" }
  get "/admin/promo_codes/:id",     to: "cloud_only#show", as: :admin_promo_code,          defaults: { feature: "promo codes" }
  get "/docs(/*path)",              to: "cloud_only#show", as: :docs,                      defaults: { feature: "docs" }
  get "/feedback",                  to: "cloud_only#show", as: :feedback,                  defaults: { feature: "feedback" }
  get "/lazy/features_grid",        to: "cloud_only#show", as: :lazy_features_grid,        defaults: { feature: "lazy frame" }
  get "/lazy/templates_grid",       to: "cloud_only#show", as: :lazy_templates_grid,       defaults: { feature: "lazy frame" }
  get "/lazy/pricing_tiers",        to: "cloud_only#show", as: :lazy_pricing_tiers,        defaults: { feature: "lazy frame" }

  get "up" => "rails/health#show", as: :rails_health_check

  # Self-hosters land at sign-in. After auth they're routed to /dashboard.
  root to: redirect("/users/sign_in")
end
