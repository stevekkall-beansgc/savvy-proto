Rails.application.routes.draw do
  get "/health", to: "graphql#health"
  post "/graphql", to: "graphql#execute"
end
