require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module WokkuHarness
  class Application < Rails::Application
    # Never dump schema.rb after migrating: the schema's single source is
    # the engine's baseline migration (structure.sql). A dumped schema.rb
    # would take precedence in db:prepare on an empty database and its
    # uuidv7() defaults don't load on stock Postgres 16.
    config.active_record.dump_schema_after_migration = false

    config.load_defaults 8.1
    config.eager_load = ENV["HARNESS_EAGER_LOAD"] == "1"
    config.hosts.clear

    # One secret to set: everything else derives from it. Compose requires
    # SECRET_KEY_BASE (:?), and production refuses the insecure default.
    secret = ENV.fetch("SECRET_KEY_BASE", "wokku-harness-insecure-secret-key-base-0000")
    if Rails.env.production? && secret.start_with?("wokku-harness-insecure")
      raise "SECRET_KEY_BASE must be set in production (openssl rand -hex 64)"
    end
    config.secret_key_base = secret

    # Active Record encryption protects env vars, backup credentials, and
    # cert private keys — derive real keys from the secret instead of ever
    # shipping hardcoded ones. AR_ENC_* env vars override for key rotation.
    kg = ActiveSupport::KeyGenerator.new(secret, hash_digest_class: OpenSSL::Digest::SHA256)
    derive = ->(salt) { kg.generate_key(salt, 32).unpack1("H*") }
    config.active_record.encryption.primary_key         = ENV.fetch("AR_ENC_PRIMARY")       { derive.call("wokku_ar_primary") }
    config.active_record.encryption.deterministic_key   = ENV.fetch("AR_ENC_DETERMINISTIC") { derive.call("wokku_ar_deterministic") }
    config.active_record.encryption.key_derivation_salt = ENV.fetch("AR_ENC_SALT")          { derive.call("wokku_ar_salt") }
    # Read pre-encryption / plaintext rows (self-host installs predating a
    # column becoming encrypted; also lets test fixtures store plaintext).
    config.active_record.encryption.support_unencrypted_data = true

    # The standard install serves the dashboard behind Caddy's TLS on
    # 80/443, so in production force HTTPS: this sets Strict-Transport-
    # Security (HSTS), the Secure flag on cookies, and an http->https
    # redirect. assume_ssl trusts Caddy's X-Forwarded-Proto so there's no
    # redirect loop. Opt out with WOKKU_FORCE_SSL=0 for a plain-http or
    # localhost-only deployment.
    if Rails.env.production? && ENV["WOKKU_FORCE_SSL"] != "0"
      config.assume_ssl = true
      config.force_ssl  = true
    end

    # Test env: capture mail instead of hitting SMTP, and give mailer URLs
    # a host (self-host production sets these from the deployment domain).
    if Rails.env.test?
      config.action_mailer.delivery_method = :test
      config.action_mailer.default_url_options = { host: "wokku.cloud" }
      # Encrypt fixture values on load so deterministic-encrypted columns
      # (e.g. DeviceToken#token) honour uniqueness in specs.
      config.active_record.encryption.encrypt_fixtures = true
      # Request specs POST without a CSRF token; disable forgery protection
      # so they exercise the controller, not the token check.
      config.action_controller.allow_forgery_protection = false
      # :rescuable matches wokku-cloud's test env: RoutingError/RecordNotFound
      # render their mapped status (the Devise admin-constraint 404 specs
      # assert responses, not raises); unmapped exceptions still raise.
      config.action_dispatch.show_exceptions = :rescuable
      # No cache in tests (matches wokku-cloud): the default file store under
      # tmp/cache leaks values between examples and between runs.
      config.cache_store = :null_store
    end

    # Jobs run in-process via the Solid Queue puma plugin (config/puma.rb).
    config.active_job.queue_adapter = :solid_queue
    config.solid_queue.connects_to = nil if config.respond_to?(:solid_queue)

    # Self-host default locale is English with fallbacks (the cloud host
    # sets its own launch-market default).
    config.i18n.default_locale = ENV.fetch("WOKKU_DEFAULT_LOCALE", "en").to_sym
    config.i18n.fallbacks = [ :en ]

    # docker compose logs must show Rails output.
    if ENV["RAILS_LOG_TO_STDOUT"].present?
      config.logger = ActiveSupport::TaggedLogging.logger($stdout)
      config.log_level = :info
    end
  end
end
