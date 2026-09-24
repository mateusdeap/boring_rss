Rails.application.routes.draw do
  resource :session
  resource :preferences, only: %i[ update ]
  resources :registrations, only: %i[ new create ]
  resources :passwords, param: :token
  mount MissionControl::Jobs::Engine, at: "/jobs"

  resources :items do
    # Mark / unmark (RDR-01's one-keypress "marked" state).
    resource :mark, only: %i[ create destroy ], module: :items
  end
  # Defines the root path route ("/")
  root "feeds#index"

  resources :feeds do
    # POST /feeds/:feed_id/reading — mark every item in the feed read.
    resource :reading, only: :create, module: :feeds
  end
  resources :folders, only: %i[ update destroy ]
  # Every marked item across all feeds (the MARKED row atop the feed tree).
  get "marked", to: "marked_items#index", as: :marked_items
end
