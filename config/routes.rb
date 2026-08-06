# Engine routes — the open-source product surface. Auto-drawn into the
# host's route set (non-isolated engine); the cloud host draws its own
# billing/marketing/tunnel routes in config/routes.rb. Engine routes are
# loaded AFTER host routes; the two sets are disjoint by path and name.
Rails.application.routes.draw do
  get "/wokku/engine-smoke", to: "engine_smoke#show", as: :engine_smoke

  # Connect-a-server installer: the script is public (the token passed to
  # it is the secret); the binary ships in the control-plane image.
  get "/install/wokkud.sh", to: "install#script", as: :install_script
  get "/install/wokkud",    to: "install#binary", as: :install_binary

  # First-boot setup (zero users → create the admin; dead afterwards).
  get  "/setup", to: "setup#new",    as: :setup
  post "/setup", to: "setup#create"

  devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" }
  # Registrations are OAuth-only — redirect any lingering /users/sign_up links
  # to the sign-in page so they don't 404.
  get "/users/sign_up", to: redirect("/users/sign_in")

  # GitHub
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
        get "sections/:section", to: "apps#section", as: :sections
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
        get  :danger
        post :backup_now
        post :unlock
        post :lock
      end
      # Bundle v2 — dedicated upgrade actions. Single action per engine + verb.
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
      resource :metrics, only: [ :show ], controller: "metrics"
      # Per-app HTTP-request monitor (req-rate, p50/p95, error %) backed
      # by Vector-shipped RequestAggregate buckets. Distinct from the
      # `metrics` page (which shows CPU/memory container stats).
      resource :monitor, only: [ :show ], module: "apps", controller: "monitor"
      resource :performance, only: [ :show ], module: "apps", controller: "performance" do
        post :rotate_token
      end
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
        get :settings
      end
      # Sumopod-style monitor page — Active Conns / DB Size / Cache Hit
      # Ratio / Live status + Query Performance table (Slowest /
      # Most Time / Most Called tabs).
      resource :monitor, only: [ :show ], module: "databases", controller: "monitor"
      resources :backups, only: [ :index, :create ], controller: "backups" do
        member do
          get :download
          post :restore
        end
      end
    end

    # Old "resources" URL kept as redirect so external links and bookmarks
    # don't 404 after the Heroku-style "add-ons" rename.
    get "/resources",        to: redirect("/dashboard/apps")
    get "/resources/*path",  to: redirect("/dashboard/apps")
    # Cloud credentials moved to /admin/cloud_credentials in Phase 3 #19.
    get "/cloud_credentials(/*path)", to: redirect("/admin/cloud_credentials")
    # Teams UI is hidden pre-launch — keep route name (helpers still
    # exist for any stragglers) but bounce visitors to the dashboard.
    # PR C of personal+multi-team refactor: legacy /dashboard/teams
    # now points at the workspaces index instead of bouncing to the
    # dashboard root.
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
    resource :usage, only: [ :show ], controller: "usage"
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

    post "ai/diagnose", to: "ai#diagnose", as: :ai_diagnose

    # PR C of personal+multi-team refactor: workspace index/new/create/show
    # plus the PR B switch backend. PR C2 adds member management.
    resources :workspaces, only: %i[index new create show] do
      member { post :switch }
      resources :members, only: %i[create update destroy],
                          controller: "team_members", as: :team_members
    end
  end

  # Admin-only namespace — gated by Devise authenticate block so non-admins
  # get a 401 from Devise before hitting any controller action. The cloud
  # host adds its own admin routes (revenue dashboard, jobs UI) on top.
  authenticate :user, ->(u) { u.admin? } do
    namespace :admin do
      resources :servers do
        collection do
          post :provision
        end
        member do
          post :sync
        end
        # Terminals and backup destinations still live in Dashboard namespace;
        # leading slash makes the controller path absolute.
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

  post "/vitals/ingest", to: "vitals_ingest#create"
  get "/v.js", to: "vitals_script#show"
  get "/docs", to: "docs#show", as: :docs
  get "/docs/search-index.json", to: "docs#search_index", as: :docs_search_index
  get "/docs/*path", to: "docs#show", as: :docs_page

  get "up" => "rails/health#show", as: :rails_health_check

  # ── REST API (product surface; the cloud host adds billing/dyno/tunnel
  # endpoints in its own config/routes/api.rb) ─────────────────────────────
  namespace :api do
    namespace :v1 do
      # Unauthenticated version probe — CLI/MCP hit this to detect their own
      # staleness before making any authenticated call. See MetaController.
      get :meta, to: "meta#show"

      # Authenticated whole-chain self-diagnosis for agents ("why is my thing
      # broken"). DB-only (no SSH) so it stays fast and still answers when a
      # host itself is unreachable. See DoctorController.
      get :doctor, to: "doctor#show"

      namespace :auth do
        post :login
        delete :logout
        get :whoami
        resources :tokens, only: [ :index, :create, :destroy ]
        post "device/code", to: "devices#code"
        post "device/token", to: "devices#token"
      end

      resources :servers, only: [ :index, :show, :create, :destroy ] do
        member do
          get :status
          post :dokku
        end
      end

      resources :apps, only: [ :index, :show, :create, :update, :destroy ] do
        member do
          post :restart
          post :stop
          post :start
          post :deploy
          post :run
          post :dokku
          post :github_connect
          delete :github_disconnect
          patch :https,        to: "apps#set_https"
          patch :cdn,          to: "apps#set_cdn"
          patch :maintenance,  to: "apps#set_maintenance"
          patch :rename,   to: "apps#rename"
          post  :clone,    to: "apps#clone"
          post  :lock,     to: "apps#lock"
          post  :unlock,   to: "apps#unlock"
          post  :transfer, to: "apps#transfer"
          get :metrics, to: "apps#metrics"
          get :monitor, to: "apps#monitor"
          get :vitals,  to: "apps#vitals"
        end
        resource :config, only: [ :show, :update, :destroy ], controller: "config"
        resources :domains, only: [ :index, :create, :destroy ] do
          member do
            post :ssl
          end
        end
        resources :releases, only: [ :index, :show ] do
          member do
            post :rollback
          end
        end
        resources :runs, only: [ :show ], controller: "runs"
        resource :ps, only: [ :show, :update ], controller: "ps"
        resource :checks, only: [ :show, :update ], controller: "checks"
        resources :logs, only: [ :index ]
        resources :deploys, only: [ :index, :show, :create ] do
          collection do
            post :uploads, to: "deploy_uploads#create"
          end
        end
        # Bundle v2 — collection routes for shared / dedicated addon management.
        # The plain :create action is kept for flag-off backward compatibility;
        # when BUNDLE_V2_ENABLED is on it returns 410 Gone.
        resources :addons, only: [ :index, :create, :destroy ] do
          collection do
            post   "shared",          to: "addons#enable_shared"
            delete "shared/:engine",  to: "addons#disable_shared", as: :disable_shared
            post   "dedicated",       to: "addons#upgrade_dedicated"
          end
        end
        resource :buildpacks, only: [ :show, :create, :destroy, :update ], controller: "buildpacks"
        resource :storage, only: [ :show, :create, :destroy ], controller: "storage"
        resources :scheduled_tasks, only: %i[index create destroy], controller: "scheduled_tasks"
        resources :previews, only: %i[index destroy], controller: "previews", param: :pr_number
        resources :dev_sessions, only: %i[create destroy], controller: "dev_sessions"
      end

      resources :templates, only: [ :index, :show ] do
        collection do
          post :deploy
        end
      end

      resources :devices, only: [ :create, :destroy ]

      resources :databases, only: [ :index, :show, :create, :destroy ] do
        member do
          post :link
          post :unlink
          post :import
          get :monitor
        end
        resources :backups, only: [ :index, :create ] do
          member do
            get :download
            post :restore
          end
        end
      end

      resources :activities, only: [ :index ]

      resources :ssh_keys, only: [ :index, :create, :destroy ]

      resources :teams, only: [ :index, :create ] do
        resources :members, only: [ :index, :create, :destroy ], controller: "team_members"
      end

      resources :notifications, only: [ :index, :create, :destroy ]

      post "ai/diagnose", to: "ai#diagnose"

      # Vector log ingest — per-server bearer token auth, no user session.
      # Lives outside the user-API auth chain because the caller is a
      # daemon on a host, not a user with an ApiToken.
      namespace :logs do
        post :ingest, to: "ingest#create"
      end

      # Vector HTTP-request ingest — parsed nginx-proxy access-log fields.
      # Same auth model as :logs above; populates RequestSample rows.
      namespace :requests do
        post :ingest, to: "ingest#create"
      end

      # wokkud host-agent ingest — per-server bearer token auth (same as :logs
      # above). Heartbeats sync vitals + agent version. Events create
      # CrashEvent records and fire owner alerts (see EventsController).
      namespace :agent do
        post :heartbeat, to: "heartbeats#create"
        post :events,    to: "events#create"
        # Signed-token archive download (local backup_store only) — the
        # token is the auth, not the agent bearer chain.
        get :archive, to: "archives#show", as: :archive
        # Phase 4c build executor: wokkud claims a pending build, streams its
        # output, and reports the outcome. Same ingest_token trust boundary.
        post "builds/:id/claim",  to: "builds#claim",  as: :build_claim
        post "builds/:id/log",    to: "builds#log",    as: :build_log
        post "builds/:id/report", to: "builds#report", as: :build_report

        # Track B B3: declarative cron sync + fire-time env fetch. wokkud
        # GETs cron/config when the heartbeat's cron_config_version differs
        # from what it last applied, then fetches an app's env right before
        # firing each entry so values are always current. cron_runs is
        # handled by Api::V1::Agent::CronRunsController.
        get "cron/config",     to: "cron_configs#show"
        get "apps/:name/env",  to: "app_envs#show", constraints: { name: /[a-z][a-z0-9-]{0,62}/ }
        post "cron_runs",      to: "cron_runs#create"

        # Phase B4 datastore-op executor: wokkud claims a pending ServiceOp,
        # streams its log, and reports the outcome. Same trust boundary as
        # builds above (mirrors BuildsController's claim/log/report).
        post "service_ops/:id/claim",  to: "service_ops#claim",  as: :service_op_claim
        post "service_ops/:id/log",    to: "service_ops#log",    as: :service_op_log
        post "service_ops/:id/report", to: "service_ops#report", as: :service_op_report

        # Phase B5a Swarm lifecycle-op executor: wokkud claims a pending
        # LifecycleOp (stack.converge/stack.remove), streams its log, and
        # reports the outcome. Same trust boundary as service_ops above.
        post "lifecycle_ops/:id/claim",  to: "lifecycle_ops#claim",  as: :lifecycle_op_claim
        post "lifecycle_ops/:id/log",    to: "lifecycle_ops#log",    as: :lifecycle_op_log
        post "lifecycle_ops/:id/report", to: "lifecycle_ops#report", as: :lifecycle_op_report

        # Phase B1 router: wokkud fetches declarative routing config when the
        # heartbeat's router_config_version differs from what it last applied.
        # tls_allowed is Caddy's on-demand-TLS `ask` gate — Caddy can't set
        # headers, so this one also accepts ?token=.
        get "router/config",      to: "routers#show",        as: :router_config
        get "router/tls_allowed", to: "routers#tls_allowed", as: :router_tls_allowed
      end
    end
  end
end
