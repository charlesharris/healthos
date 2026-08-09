# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    before_action :require_organization
    helper_method :authenticated?, :current_organization, :current_membership
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      skip_before_action :require_organization, **options
    end

    # For pages that need a signed-in user but no tenant yet — choosing an
    # organization, accepting an invitation.
    def allow_without_organization(**options)
      skip_before_action :require_organization, **options
    end
  end

  private

  def authenticated?
    resume_session
  end

  def require_authentication
    resume_session || request_authentication
  end

  def resume_session
    Current.session ||= find_session_by_cookie
  end

  def find_session_by_cookie
    Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
  end

  def request_authentication
    session[:return_to_after_authenticating] = request.url
    redirect_to new_session_path
  end

  def after_authentication_url
    session.delete(:return_to_after_authenticating) || root_url
  end

  def start_new_session_for(user)
    user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |new_session|
      Current.session = new_session
      cookies.signed.permanent[:session_id] = { value: new_session.id, httponly: true, same_site: :lax }
    end
  end

  def terminate_session
    Current.session.destroy
    cookies.delete(:session_id)
    session.delete(:organization_id)
  end

  # Establishes the tenant for this request (HO §12).
  #
  # The membership is re-resolved from the database on every request rather
  # than trusted from the cookie. The cookie only carries which organization
  # was selected; whether the user may still act there is decided here, so
  # revoking or suspending a membership takes effect on the next request
  # rather than whenever the session happens to expire.
  def require_organization
    Current.membership = resolve_membership

    return if Current.membership.present?

    if Current.user&.usable_memberships&.any?
      redirect_to organization_chooser_path
    else
      # Authenticated but with no usable membership anywhere. Not a
      # redirect loop risk: this path does not require an organization.
      redirect_to no_access_path
    end
  end

  def resolve_membership
    user = Current.user
    return nil if user.blank?

    selected = session[:organization_id]
    membership = user.usable_memberships.find_by(organization_id: selected) if selected.present?

    # Fall back to the sole membership when there is no ambiguity. With more
    # than one the user must choose, so we do not silently pick a tenant.
    if membership.nil?
      candidates = user.usable_memberships.to_a
      membership = candidates.first if candidates.one?
      session[:organization_id] = membership&.organization_id
    end

    membership
  end

  def current_organization = Current.organization
  def current_membership = Current.membership
end
