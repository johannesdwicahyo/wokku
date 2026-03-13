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

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard/apps#index"
end
