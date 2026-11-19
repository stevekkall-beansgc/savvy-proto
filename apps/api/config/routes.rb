Rails.application.routes.draw do
  get "/health", to: "graphql#health"
  post "/graphql", to: "graphql#execute"
  match "/demo-session", to: "graphql#demo_session", via: [:post, :delete]
end
