# frozen_string_literal: true

module Identity
  # Resolves an external identifier to a Subject, creating one if needed
  # (HO §113 lists this as Identity::ResolveSubject).
  #
  # Must be idempotent: ingestion is at-least-once (S2C-020), so the same
  # source record may arrive repeatedly and must never yield two subjects for
  # one person. Idempotency rests on the database's unique index over
  # (organization_id, system, value), not on a check-then-insert — under
  # concurrent ingestion the check-then-insert race is exactly what the
  # constraint exists to lose.
  class ResolveSubject
    Result = Struct.new(:subject, :created, keyword_init: true) do
      def created? = created
    end

    def self.call(...) = new(...).call

    def initialize(organization:, system:, value:, timezone: "UTC", source: nil)
      @organization = organization
      @system = system.to_s
      @value = value.to_s
      @timezone = timezone
      @source = source
    end

    def call
      existing = find_existing
      return Result.new(subject: existing, created: false) if existing

      create_subject_with_identifier
    rescue ActiveRecord::RecordNotUnique
      # Lost the race with a concurrent resolution of the same identifier.
      # The other transaction committed a subject; adopt it rather than
      # failing, which is what makes retries safe.
      found = find_existing
      raise if found.nil?

      Result.new(subject: found, created: false)
    end

    private

    attr_reader :organization, :system, :value, :timezone, :source

    def find_existing
      SubjectIdentifier
        .where(organization_id: organization.id, system: system, value: value)
        .first
        &.subject
    end

    def create_subject_with_identifier
      subject = nil

      ActiveRecord::Base.transaction(requires_new: true) do
        subject = Subject.create!(organization: organization, timezone: timezone)
        SubjectIdentifier.create!(
          organization: organization, subject: subject,
          system: system, value: value, source_id: source&.id
        )
      end

      Result.new(subject: subject, created: true)
    end
  end
end
