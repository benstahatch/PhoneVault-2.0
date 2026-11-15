Rails.application.routes.draw do
  root "sessions#new"

  # short custom URLs; each route is named after its path (login_path, signup_path, ...)
  get "login", to: "sessions#new"
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy"
  get "signup", to: "registrations#new"
  post "signup", to: "registrations#create"
  get "dashboard", to: "dashboard#show"
  get "activity", to: "activity#index"

  resources :devices, only: %i[index new create edit update] do
    resource :backup_location, only: [] do
      get :directories
      post :validate_path
    end
    resources :backup_runs, only: %i[index new create] do
      resources :backup_files, only: :destroy do
        member do
          get :restore
          get :preview
        end
      end
    end
  end

  # /trash lists the user's trashed backup files; /trash/retention/edit sets how long they stay
  resources :trash, as: :trashed_files, only: %i[index destroy] do
    patch :restore, on: :member
  end
  resource :trash_retention_settings, path: "trash/retention", only: %i[edit update] do
    post :confirm
  end

  # health check for load balancers and uptime monitors: 200 if the app boots, otherwise 500
  get "up" => "rails/health#show", as: :rails_health_check
end
