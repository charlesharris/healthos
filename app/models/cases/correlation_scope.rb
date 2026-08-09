# frozen_string_literal: true

module Cases
  # The serialization point for correlation (HO §35).
  #
  # Exists solely to be locked. Correlation for one subject in one domain must
  # be serial or three simultaneous Signals create three Cases — the exact
  # failure S2C-007 forbids and HO §120 makes a must-pass test.
  class CorrelationScope < ApplicationRecord
    self.table_name = "case_correlation_scopes"

    belongs_to :organization
    belongs_to :subject

    validates :domain_key, presence: true

    # Find-or-create then lock. The create races with itself, so the unique
    # index resolves it and we re-read — the same pattern used everywhere
    # else here, because check-then-insert loses under concurrency.
    def self.lock_for!(organization:, subject:, domain_key:)
      scope = find_or_create_scope(organization, subject, domain_key)
      # FOR UPDATE. Every other correlation for this subject+domain waits
      # here until this transaction commits.
      lock.find(scope.id)
    end

    # The create must run in its own SAVEPOINT.
    #
    # This method is called inside the correlation transaction, and when two
    # threads race to create the same scope one of them loses on the unique
    # index. In PostgreSQL a failed statement aborts the ENTIRE enclosing
    # transaction — every subsequent statement then fails with
    # InFailedSqlTransaction, so a plain `rescue RecordNotUnique` cannot
    # recover and the whole correlation dies.
    #
    # `requires_new: true` issues a SAVEPOINT, so only the failed insert rolls
    # back and the outer transaction survives to re-read the winner. Found by
    # the HO §120 concurrency spec, which is precisely the failure it exists
    # to surface.
    def self.find_or_create_scope(organization, subject, domain_key)
      existing = find_by(organization_id: organization.id, subject_id: subject.id,
                         domain_key: domain_key)
      return existing if existing

      begin
        transaction(requires_new: true) do
          create!(organization: organization, subject: subject, domain_key: domain_key)
        end
      rescue ActiveRecord::RecordNotUnique
        find_by!(organization_id: organization.id, subject_id: subject.id, domain_key: domain_key)
      end
    end
  end
end
