Rails.application.routes.draw do
  resource :session
  resources :registrations, only: %i[ new create ]
  resources :passwords, param: :token
  mount MissionControl::Jobs::Engine, at: "/jobs"

  resources :items
  # Defines the root path route ("/")
  root "feeds#index"

  resources :feeds
end
