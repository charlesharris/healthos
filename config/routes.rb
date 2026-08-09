Rails.application.routes.draw do
  namespace :admin do
      resources :audit_events
      resources :domain_events
      resources :invitations
      resources :organizations
      resources :organization_memberships
      resources :sessions
      resources :staff_members
      resources :teams
      resources :team_memberships
      resources :users

      # Purpose-built evidence tooling (HO §157). Read-only, outside
      # Administrate — health evidence is excluded from generic CRUD.
      get "provenance/:id", to: "provenance#show", as: :provenance

      root to: "organizations#index"
    end
  resource :session
  resources :passwords, param: :token

  # Epic 001-02 tenant surfaces. Minimal by intent — the Ops Queue (epic 002)
  # is the real product surface.
  get  "organizations/chooser", to: "organizations#chooser", as: :organization_chooser
  post "organizations/choose",  to: "organizations#choose",  as: :choose_organization
  get  "no-access",             to: "organizations#no_access", as: :no_access
  get  "members",               to: "organizations#members", as: :members

  # The Ops Queue — the daily product surface (HO §84), with Quick Review
  # (HO §88) as the Case member route.
  #
  # Assignment and state are separate singular resources rather than member
  # verbs on cases. Each maps to a controller that does exactly one thing and
  # delegates to a service (Cases::Assign, Cases::Transition), which is what
  # keeps S2C-013 mechanically true: there is no update action on the Case
  # itself to reach.
  namespace :ops do
    resources :cases, only: %i[index show] do
      resource :assignment, only: %i[update], controller: "assignments"
      resource :state, only: %i[update], controller: "case_states"
    end
  end

  resources :invitations, only: %i[index create]
  get  "invitations/accept/:token", to: "invitations#show",   as: :accept_invitation
  post "invitations/accept",        to: "invitations#accept"

  root "ops/cases#index"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
