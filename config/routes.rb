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

  # Every screen has a URL: a list (/groups/:id, /feeds/:id, /marked) and
  # an item open within it. /items/:id is the item within its own feed.
  resources :feeds do
    resources :items, only: :show
    # POST /feeds/:feed_id/reading — mark every item in the feed read.
    resource :reading, only: :create, module: :feeds
    # FETCH NOW in the feed view.
    resource :fetch, only: :create, module: :feeds
  end
  resources :folders, only: %i[ update destroy ]
  # Groups mode's rivers: /groups/all, /groups/ungrouped, /groups/:folder_id.
  resources :groups, only: :show do
    resources :items, only: :show
    # [S] TIME / FEED, remembered per group.
    resource :sort, only: :update, module: :groups
    # [⇧R] mark the whole river read.
    resource :reading, only: :create, module: :groups
  end
  # Every marked item across all feeds (the MARKED row under the left pane).
  get "marked", to: "marked_items#index", as: :marked_items
  get "marked/items/:id", to: "items#show", as: :marked_item
end
