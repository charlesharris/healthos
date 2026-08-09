# frozen_string_literal: true

module Admin
  # Base controller for the platform staff admin UI.
  #
  # This surface is a deliberate, narrow exception to INV-31: staff read across
  # organizations, which every other path in the application is forbidden to
  # do (HO §12). Three things keep that exception honest:
  #
  #   1. Access requires an active StaffMember, not an organization role.
  #   2. Every action is written to audit_events — HO §92 lists "Admin
  #      configuration changed"; HO §157 requires support access to be audited.
  #   3. It runs as healthos_app like everything else, NOT healthos_admin. The
  #      append-only grants therefore still apply, so no screen here can mutate
  #      evidence even if a dashboard were added by mistake (ADR-002 4a).
  #
  # Scope is config and identity only. Health evidence — subjects, telemetry,
  # signals, cases, analytical artifacts — is deliberately absent. Those get
  # the purpose-built read-only tooling HO §157 enumerates (provenance
  # drilldown in 001-08, support tooling in 005-15), because inspecting
  # evidence is a task-shaped problem, not a CRUD-shaped one.
  class ApplicationController < Administrate::ApplicationController
    # Resources that may be viewed but never modified here. Some are
    # append-only at the database level and would fail anyway; listing them
    # means the UI does not offer buttons that cannot work.
    READ_ONLY_RESOURCES = %w[audit_events domain_events].freeze

    # Administrate's base controller descends from ActionController::Base, not
    # from our ApplicationController, so session handling has to be included
    # explicitly — otherwise Current.session is always nil here.
    include Authentication

    # Staff are platform-level and need not belong to any organization, so the
    # tenant requirement is skipped. StaffMember is the gate instead.
    allow_without_organization

    before_action :require_staff
    before_action :enforce_read_only
    after_action :record_audit_event, only: %i[create update destroy]

    private

    def enforce_read_only
      return unless READ_ONLY_RESOURCES.include?(controller_name)
      return if %w[index show].include?(action_name)

      deny
    end

    # Administrate's documented authorization hook (docs/authorization.md).
    # Every New/Edit/Destroy link is gated on it via accessible_action?, so
    # overriding here removes the buttons; enforce_read_only above refuses the
    # request. Both are needed — hiding a control is presentation, refusing it
    # is the control.
    def authorized_action?(resource, action_name)
      return false if READ_ONLY_RESOURCES.include?(controller_name) &&
                      !%w[index show].include?(action_name.to_s)

      super
    end

    def require_staff
      # require_authentication (from Authentication) has already redirected an
      # unauthenticated visitor by this point.
      return if Current.user.blank?

      @staff_member = StaffMember.for(Current.user)

      # 404 rather than 403: a non-staff user should not learn that this
      # surface exists (HO §123 treats enumeration as a security concern).
      deny if @staff_member.nil?
    end

    def current_staff_member = @staff_member

    def deny
      render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
    end

    def record_audit_event
      return unless response.successful? || response.redirect?

      AuditEvent.record!(
        event_type: "admin.#{controller_name}.#{action_name}",
        actor: Current.user,
        organization: audited_organization,
        staff_member: current_staff_member,
        metadata: {
          "resource_type" => resource_class.name,
          "resource_id" => requested_resource&.id,
          # Field names only, never values — HO §92: "Avoid raw PHI in audit
          # metadata unless required."
          "changed_fields" => changed_field_names
        }.compact
      )
    end

    # Best-effort tenant attribution. Platform-level records (a User, a
    # StaffMember) genuinely have none, which is why audit_events.organization_id
    # is nullable.
    def audited_organization
      record = requested_resource
      return nil if record.nil?
      return record if record.is_a?(Organization)

      record.organization if record.respond_to?(:organization)
    rescue StandardError
      nil
    end

    def changed_field_names
      return [] if action_name == "destroy"

      params.fetch(resource_class.name.underscore.to_sym, {}).keys
    rescue StandardError
      []
    end

    def requested_resource
      @requested_resource ||= begin
        resource_class.find(params[:id])
      rescue StandardError
        nil
      end
    end
  end
end
