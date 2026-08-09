# frozen_string_literal: true

# Application-level encryption for subject identity fields (HO §10.3:
# "Identity fields should use application-level encryption where appropriate").
#
# Keys come from the environment rather than encrypted credentials. Rails'
# default (credentials + config/master.key) would require RAILS_MASTER_KEY to
# be present in CI as a repository secret; environment keys keep CI green
# without one, and make key rotation an infrastructure concern rather than a
# commit.
#
# The development and test defaults below are FIXED AND PUBLIC. That is
# deliberate and safe here only because docs/implementation/prototype-scope.md
# records that this system will hold synthetic data exclusively. They exist so
# encryption is genuinely exercised — the invariant is tested rather than
# assumed — not to protect anything.
#
# Production MUST supply real keys via the environment and will refuse to boot
# without them. Before real PHI, HO §11's pilot gate additionally requires
# SSO, MFA, session and support-access review.

module HealthosEncryptionKeys
  # Non-production placeholders. Regenerate real ones with:
  #   bin/rails db:encryption:init
  DEV_PRIMARY_KEY     = "development_only_primary_key_not_secret_00"
  DEV_DETERMINISTIC   = "development_only_deterministic_key_nope_01"
  DEV_KEY_DERIVATION  = "development_only_key_derivation_salt_xx_02"

  # Rails' generated Dockerfile precompiles assets with RAILS_ENV=production,
  # so a hard raise here fails the image build even though nothing touches the
  # database. SECRET_KEY_BASE_DUMMY is the signal Rails itself uses to mark
  # that build-time context; honouring it keeps the production guard while
  # letting the image build.
  def self.build_context?
    ENV["SECRET_KEY_BASE_DUMMY"].present?
  end

  def self.fetch(env_name, development_default)
    value = ENV[env_name]
    return value if value.present?

    if Rails.env.local? || build_context?
      development_default
    else
      raise "#{env_name} must be set outside development and test. " \
            "Generate keys with `bin/rails db:encryption:init`."
    end
  end
end

Rails.application.configure do
  config.active_record.encryption.primary_key =
    HealthosEncryptionKeys.fetch("AR_ENCRYPTION_PRIMARY_KEY", HealthosEncryptionKeys::DEV_PRIMARY_KEY)

  config.active_record.encryption.deterministic_key =
    HealthosEncryptionKeys.fetch("AR_ENCRYPTION_DETERMINISTIC_KEY", HealthosEncryptionKeys::DEV_DETERMINISTIC)

  config.active_record.encryption.key_derivation_salt =
    HealthosEncryptionKeys.fetch("AR_ENCRYPTION_KEY_DERIVATION_SALT", HealthosEncryptionKeys::DEV_KEY_DERIVATION)

  # Encrypted columns must not leak their plaintext into logs.
  config.active_record.encryption.support_unencrypted_data = false
end
