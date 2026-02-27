Rails.application.routes.draw do
  get 'terminal', to: 'terminals#show'
  root to: 'terminals#show'
end
