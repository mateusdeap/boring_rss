Rails.application.routes.draw do
  mount MissionControl::Jobs::Engine, at: "/jobs"

  resources :items
  # Defines the root path route ("/")
  root "feeds#index"

  resources :feeds
end
