Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  # Epic 001-02 tenant surfaces. Minimal by intent — the Ops Queue (epic 002)
  # is the real product surface.
  get  "organizations/chooser", to: "organizations#chooser", as: :organization_chooser
  post "organizations/choose",  to: "organizations#choose",  as: :choose_organization
  get  "no-access",             to: "organizations#no_access", as: :no_access
  get  "members",               to: "organizations#members", as: :members

  resources :invitations, only: %i[index create]
  get  "invitations/accept/:token", to: "invitations#show",   as: :accept_invitation
  post "invitations/accept",        to: "invitations#accept"

  root "organizations#members"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
