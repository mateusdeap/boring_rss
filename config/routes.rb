Rails.application.routes.draw do
  resources :items
  # Defines the root path route ("/")
  root "feeds#index"

  resources :feeds
end
