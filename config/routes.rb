Rails.application.routes.draw do
  resource :session
  resource :preferences, only: %i[ update ]
  resources :registrations, only: %i[ new create ]
  resources :passwords, param: :token
  mount MissionControl::Jobs::Engine, at: "/jobs"

  resources :items do
    # The reader's [J] OPEN FIRST UNREAD, when no item list is loaded.
    get :first_unread, on: :collection
    # Mark / unmark (RDR-01's one-keypress "marked" state).
    resource :mark, only: %i[ create destroy ], module: :items
    # Mark read / unread — the reader's [U] toggle.
    resource :reading, only: %i[ create destroy ], module: :items
  end
  # [R] POLL NOW: poll the signed-in user's feeds right away.
  resource :poll, only: :create
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
