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
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "dashboard/apps#index"
end
