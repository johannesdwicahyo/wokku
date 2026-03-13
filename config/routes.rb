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
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard/apps#index"
end
