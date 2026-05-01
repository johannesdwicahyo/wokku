Rails.application.routes.draw do
  # Canonicalize www → apex. wokku.cloud is the brand host; www is
  # listed on kamal-proxy only to avoid 404s from typed-in URLs.
  constraints host: "www.wokku.cloud" do
    match "(*path)", to: redirect { |params, _req| "https://wokku.cloud/#{params[:path]}" }, via: :all
  end

  devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" }
  # Registrations are OAuth-only — redirect any lingering /users/sign_up links
  # to the sign-in page so they don't 404.
  get "/users/sign_up", to: redirect("/users/sign_in")

  # REST API routes live in config/routes/api.rb so they can be omitted
  # from the OSS sync (which strips app/controllers/api/ entirely).
  # When the file isn't present (OSS UI install), the API namespace is
  # absent; dashboard routes below are unaffected.
  draw :api if Rails.root.join("config/routes/api.rb").exist?

  # CLI distribution. wokku-cloud is the canonical source for the CLI
  # script + installer; the Homebrew tap and the curl-pipe-bash install
  # both point at these URLs (rather than the public OSS repo's raw
  # GitHub URL) so the OSS UI repo can be stripped/rebuilt without
  # breaking `brew install wokku`. See PublicCliController.
  get "/cli/wokku",      to: "public_cli#wokku"
  get "/cli/install.sh", to: "public_cli#install"

  # GitHub
  get "/github/callback", to: "github/callbacks#create", as: :github_callback
  post "/webhooks/github", to: "webhooks/github#create"
  post "/webhooks/gitlab", to: "webhooks/gitlab#create"
  post "/webhooks/bitbucket", to: "webhooks/bitbucket#create"
  namespace :dashboard do
    get "/", to: "dashboard#show", as: :root
    resources :templates, only: [ :index, :show, :create ]
    resources :apps do
      collection do
        get :check_name
      end
      member do
        post :restart
        post :stop
        post :start
        post :toggle_https
        post :toggle_maintenance
        post :transfer
        # Lazy-loaded Turbo Frame sections on the app show page — each
        # opens its own SSH round-trip, letting them load in parallel
        # instead of serially blocking #show.
        get :runtime_metrics_frame
        get :live_logs_frame
        get :resource_limits_frame
      end
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
      resources :log_drains, only: [ :create, :destroy ], controller: "log_drains"
      resource :metrics, only: [ :show ], controller: "metrics"
      resource :resources, only: [ :show, :create, :destroy ], controller: "resources"
      resource :scaling, only: [ :show, :update ], controller: "scaling" do
        post :change_tier
      end
      resource :checks, only: [ :show, :update ], controller: "checks"
      resource :terminal, only: [ :show ], controller: "terminals"
      get "github/repos", to: "github#repos", as: :github_repos
      post "github/connect", to: "github#connect", as: :github_connect
      delete "github/disconnect", to: "github#disconnect", as: :github_disconnect
    end
    resources :servers do
      collection do
        post :provision
      end
      member do
        post :sync
      end
      resource :terminal, only: [ :show ], controller: "terminals"
      resource :backup_destination, only: [ :edit, :update ], controller: "backup_destinations"
    end
    resources :addons, controller: "databases" do
      member do
        post :link
        post :unlink
        post :change_tier
        post :retry
      end
      resources :backups, only: [ :index, :create ], controller: "backups" do
        member do
          get :download
          post :restore
        end
      end
    end
    # Old "resources" URL kept as redirect so external links and bookmarks
    # don't 404 after the Heroku-style "add-ons" rename.
    get "/resources", to: redirect("/dashboard/addons")
    get "/resources/*path", to: redirect("/dashboard/addons/%{path}")
    resources :cloud_credentials, only: [ :index, :create, :destroy ]
    # Teams UI is hidden pre-launch — keep route name (helpers still
    # exist for any stragglers) but bounce visitors to the dashboard.
    # The Team model and team_memberships stay intact for future use.
    get "/teams(/*path)", to: redirect("/dashboard"), as: :teams
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
    resources :promo_redemptions, only: [ :create ]
    resources :promo_codes, only: [ :index, :create, :destroy ]
    get "/admin", to: "admin#show", as: :admin
    resource :profile, only: [ :show, :edit, :update ], controller: "profile"
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
  end

  # Enterprise features
  namespace :dashboard do
    resource :billing, only: [ :show ], controller: "billing" do
      member do
        post :pay
        post :deposit
        post :deposit_stripe
        get :export
      end
    end
    resource :payment_method, only: [ :create, :destroy ], controller: "payment_methods" do
      post :confirm
    end
    post "ai/diagnose", to: "ai#diagnose", as: :ai_diagnose
  end

  post "/webhooks/stripe", to: "webhooks/stripe#create"
  post "/webhooks/ipaymu", to: "webhooks/ipaymu#create"

  # Clean URL shortcuts
  get "/apps", to: redirect("/dashboard/apps")
  get "/apps/*path", to: redirect("/dashboard/apps/%{path}")
  get "/templates", to: redirect("/dashboard/templates")
  get "/servers", to: redirect("/dashboard/servers")
  get "/activity", to: redirect("/dashboard/activities")

  # Locale switching (public, no auth required)
  post "/locale", to: "locales#update", as: :public_locale

  # Marketing pages
  get "/deploy", to: "pages#deploy"
  get "/pricing", to: "pages#pricing"
  get "/privacy", to: "pages#privacy"
  get "/terms", to: "pages#terms"
  get "/faq", to: "pages#faq"
  get "/refund", to: "pages#refund"
  get "/blog", to: "blog#index", as: :blog
  get "/blog/:slug", to: "blog#show", as: :blog_post, constraints: { slug: /[a-z0-9\-]+/ }
  get "/feedback", to: "feedback#new", as: :feedback
  post "/feedback", to: "feedback#create"
  get "/status", to: "status#show", as: :status
  get "/docs", to: "docs#show", as: :docs
  get "/docs/search-index.json", to: "docs#search_index", as: :docs_search_index
  get "/docs/*path", to: "docs#show", as: :docs_page

  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#landing"
end
