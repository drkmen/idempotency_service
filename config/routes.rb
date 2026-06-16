Rails.application.routes.draw do
  post 'idempotency/check', to: 'idempotency#check'
  post 'idempotency/commit', to: 'idempotency#commit'
  get 'health', to: 'idempotency#health'
  get 'ready', to: 'idempotency#ready'

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
end
