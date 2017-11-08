Rails.application.routes.draw do
  root "pages#show", page: "home"
  get "/pages/:page" => "pages#show"

  get '/auth/:provider/callback', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy'
end
