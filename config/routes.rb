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
        resources :dynos, only: [:index, :update], controller: "dynos"
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

      resource :billing, only: [], controller: "billing" do
        get :current_plan
        post :create_checkout
        post :portal
      end
    end
  end

  namespace :webhooks do
    post :stripe, to: "stripe#create"
  end

  namespace :dashboard do
    resources :apps do
      resources :config, only: [:index, :create, :update, :destroy], controller: "config"
      resources :domains, only: [:index, :create, :destroy], controller: "domains"
      resources :releases, only: [:index], controller: "releases" do
        collection do
          post :deploy
        end
      end
      resource :logs, only: [:show], controller: "logs"
      resource :metrics, only: [:show], controller: "metrics"
    end
    resources :servers do
      member do
        post :sync
      end
    end
    resources :databases
    resources :teams
    resource :profile, only: [:show, :edit, :update], controller: "profile"
  end

  # Marketing pages
  get "/pricing", to: "pages#pricing"
  get "/docs", to: "pages#docs"

  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#landing"
end
