# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges,
  # import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # A cross-tenant reference is a bug or an attack, never routine. Render 404
  # rather than 403 so the response does not confirm that the record exists in
  # some other organization (HO §123 lists ID enumeration as a security test).
  rescue_from Tenanted::Query::CrossTenantError,
              ApplicationPolicy::CrossTenantError,
              ActiveRecord::RecordNotFound,
              with: :not_found

  # The rail hides the Admin entry from anyone who is not platform staff.
  # Memoized because the layout asks on every request; nil is a valid answer
  # and is cached as one.
  helper_method :current_staff_member
  def current_staff_member
    return @current_staff_member if defined?(@current_staff_member)

    @current_staff_member = StaffMember.for(Current.user)
  end

  private

  def not_found
    respond_to do |format|
      format.html { render file: Rails.public_path.join("404.html"), status: :not_found, layout: false }
      format.json { render json: { error: "not_found" }, status: :not_found }
      format.any  { head :not_found }
    end
  end

  # Authorization entry point (HO §11: use policy objects). Always resolves
  # against the membership, never the bare user.
  def authorize!(record, action, policy_class: nil)
    klass = policy_class || "#{record.is_a?(Class) ? record : record.class}Policy".constantize
    policy = klass.new(membership: Current.membership, record: record.is_a?(Class) ? nil : record)

    raise ApplicationPolicy::CrossTenantError, "not permitted" unless policy.public_send(action)

    policy
  end
end
