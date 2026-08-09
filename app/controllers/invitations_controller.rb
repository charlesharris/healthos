# frozen_string_literal: true

# Minimal invitation UI (HO §11 v0.1: "invitation-based organization
# membership"). Issuing requires an organization context; accepting
# deliberately does not, since the invitee may have no membership yet.
class InvitationsController < ApplicationController
  allow_unauthenticated_access only: %i[show accept]

  def index
    authorize!(Invitation, :index?)
    @invitations = Invitation.where(organization: Current.organization).order(created_at: :desc)
  end

  def create
    authorize!(Invitation, :create?)

    _invitation, raw_token = Invitation.issue!(
      organization: Current.organization,
      email_address: params[:email_address],
      role: params[:role],
      invited_by: Current.user
    )

    # Epic 001-02 is minimal UI. Delivering the token by email lands with the
    # mailer work; surfacing it here keeps the flow testable without
    # pretending an email was sent.
    redirect_to invitations_path, notice: "Invitation link: #{accept_invitation_url(token: raw_token)}"
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    redirect_to invitations_path, alert: "Could not invite: #{e.class}"
  end

  def show
    @invitation = Invitation.find_outstanding_by_token(params[:token])

    # An expired, consumed or unknown token must all look identical, so a
    # guesser learns nothing (HO §123 ID enumeration).
    raise ActiveRecord::RecordNotFound if @invitation.nil?

    @token = params[:token]
  end

  def accept
    invitation = Invitation.find_outstanding_by_token(params[:token])
    raise ActiveRecord::RecordNotFound if invitation.nil?

    user = User.find_by(email_address: invitation.email_address) ||
           User.create!(email_address: invitation.email_address, password: params[:password])

    membership = invitation.accept!(user)

    start_new_session_for(user)
    session[:organization_id] = membership.organization_id
    redirect_to members_path, notice: "Welcome to #{membership.organization.name}"
  rescue ActiveRecord::RecordNotUnique
    redirect_to new_session_path, alert: "You are already a member of that organization."
  end
end
