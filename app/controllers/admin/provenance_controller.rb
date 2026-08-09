# frozen_string_literal: true

module Admin
  # Provenance drilldown: canonical value → raw envelope → stored payload
  # (epic 001-08; HO §21, §157).
  #
  # Deliberately NOT an Administrate dashboard. Health evidence is excluded
  # from generic CRUD by spec (spec/admin/admin_scope_spec.rb), and inspecting
  # evidence is a task-shaped problem rather than a resource-shaped one: the
  # question is "where did this number come from", which a CRUD index cannot
  # express.
  #
  # Strictly read-only, and reached through the same staff gate and audit as
  # the rest of the admin surface. Viewing evidence is audited because HO §92
  # lists it and HO §157 requires support access to be audited.
  class ProvenanceController < ApplicationController
    def show
      @observation = Observation.find(params[:id])
      @envelope = @observation.raw_envelope
      @group = @observation.observation_group
      @siblings = @group ? @group.observations.where.not(id: @observation.id) : Observation.none

      # Verified on read (ADR-002 4b). If the stored bytes no longer match the
      # recorded hash we show the failure rather than the payload — a
      # drilldown that silently rendered altered evidence would be worse than
      # one that errors (INV-4, INV-5, HO §131).
      begin
        @payload = @envelope.payload
        @integrity = :verified
      rescue Storage::RawPayloadStore::IntegrityError => e
        @payload = nil
        @integrity = :failed
        @integrity_error = e.message
      rescue StandardError => e
        @payload = nil
        @integrity = :unavailable
        @integrity_error = "#{e.class}: #{e.message}"
      end

      AuditEvent.record!(
        event_type: "admin.provenance.viewed",
        actor: Current.user,
        organization: @observation.organization,
        staff_member: current_staff_member,
        metadata: {
          "observation_id" => @observation.id,
          "raw_envelope_id" => @envelope.id,
          "integrity" => @integrity.to_s
        }
      )
    end
  end
end
