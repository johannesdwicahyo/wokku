Rails.application.routes.draw do
  devise_for :users

  namespace :api do
    namespace :v1 do
      namespace :auth do
        post :login
        delete :logout
        get :whoami
        resources :tokens, only: [:index, :create, :destroy]
      end

      resources :servers, only: [:index, :show, :create, :destroy] do
        member do
          get :status
        end
      end

      resources :apps, only: [:index, :show, :create, :update, :destroy] do
        member do
          post :restart
          post :stop
          post :start
        end
        resource :config, only: [:show, :update, :destroy], controller: "config"
        resources :domains, only: [:index, :create, :destroy] do
          member do
            post :ssl
          end
        end
        resources :releases, only: [:index, :show] do
          member do
            post :rollback
          end
        end
        resource :ps, only: [:show, :update], controller: "ps"
        resources :logs, only: [:index]
      end

      resources :databases, only: [:index, :show, :create, :destroy] do
        member do
          post :link
          post :unlink
        end
      end

      resources :ssh_keys, only: [:index, :create, :destroy]

      resources :teams, only: [:index, :create] do
        resources :members, only: [:index, :create, :destroy], controller: "team_members"
      end

      resources :notifications, only: [:index, :create, :destroy]
    end
  end

  # GitHub
  get "/github/callback", to: "github/callbacks#create", as: :github_callback
  post "/webhooks/github", to: "webhooks/github#create"

  namespace :dashboard do
    resources :templates, only: [:index, :show, :create]
    resources :apps do
      member do
        post :restart
        post :stop
        post :start
      end
      resources :config, only: [:index, :create, :update, :destroy], controller: "config"
      resources :domains, only: [:index, :create, :destroy], controller: "domains" do
        member do
          post :ssl
        end
      end
      resources :releases, only: [:index], controller: "releases" do
        collection do
          post :deploy
        end
      end
      resources :deploys, only: [:show], controller: "deploys"
      resource :logs, only: [:show], controller: "logs"
      resource :metrics, only: [:show], controller: "metrics"
      resource :scaling, only: [:show, :update], controller: "scaling"
      resource :terminal, only: [:show], controller: "terminals"
      get "github/repos", to: "github#repos", as: :github_repos
      post "github/connect", to: "github#connect", as: :github_connect
      delete "github/disconnect", to: "github#disconnect", as: :github_disconnect
    end
    resources :servers do
      member do
        post :sync
      end
      resource :terminal, only: [:show], controller: "terminals"
    end
    resources :databases do
      member do
        post :link
        post :unlink
      end
    end
    resources :teams
    resources :notifications, only: [:index, :create, :destroy]
    resource :profile, only: [:show, :edit, :update], controller: "profile"
  end

  # Load Enterprise Edition routes if available
  ee_routes = Rails.root.join("ee/config/routes/ee.rb")
  instance_eval(File.read(ee_routes)) if ee_routes.exist?

  # Marketing pages
  get "/pricing", to: "pages#pricing"
  get "/docs", to: "pages#docs"

  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#landing"
end
