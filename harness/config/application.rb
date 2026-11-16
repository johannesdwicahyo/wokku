require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)

module WokkuHarness
  # Requests that reached Puma directly (no Caddy X-Forwarded-Proto): the
  # same-box agent, Caddy's TLS `ask` gate, the installer. See force_ssl.
  LOCAL_CONTROL_REQUEST = ->(request) { request.get_header("HTTP_X_FORWARDED_PROTO").blank? }

  # Self-host mail: links point at this install's domain, senders use it
  # (never wokku.cloud), and SMTP comes from SMTP_* in .env. Without an SMTP
  # server, delivery is skipped (logged) instead of failing every job.
  def self.mail_settings(env)
    domain = env.fetch("WOKKU_CANONICAL_DOMAIN", "localhost")
    smtp   = env["SMTP_ADDRESS"].presence
    {
      default_url_options: { host: domain, protocol: env["WOKKU_FORCE_SSL"] == "0" ? "http" : "https" },
      from_defaults: {
        "MAIL_FROM"         => "Wokku <noreply@#{domain}>",
        "MAIL_FROM_HELLO"   => "Wokku <noreply@#{domain}>",
        "MAIL_FROM_SUPPORT" => "Wokku Security <noreply@#{domain}>"
      },
      perform_deliveries: !smtp.nil?,
      delivery_method: smtp ? :smtp : :test,
      smtp_settings: smtp && {
        address: smtp,
        port: env.fetch("SMTP_PORT", "587").to_i,
        user_name: env["SMTP_USERNAME"].presence,
        password: env["SMTP_PASSWORD"].presence,
        authentication: (:plain if env["SMTP_USERNAME"].present?),
        enable_starttls_auto: true
      }.compact
    }
  end

  class Application < Rails::Application
    # Never dump schema.rb after migrating: the schema's single source is
    # the engine's baseline migration (structure.sql). A dumped schema.rb
    # would take precedence in db:prepare on an empty database and its
    # uuidv7() defaults don't load on stock Postgres 16.
    config.active_record.dump_schema_after_migration = false
    # A fresh (empty) database loads the engine's structure.sql — schema AND
    # its applied-migrations list — before migrating, so migrations already
    # folded into the dump never re-run (that broke fresh installs from
    # 2026-10-19: DuplicateColumn). Never dumped back (flag above).
    config.active_record.schema_format = :sql

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
    # redirect. Rails reads Caddy's X-Forwarded-Proto, so browser traffic
    # is https. NOT assume_ssl: that made the agent's loopback http calls
    # look https too, so every URL handed to the agent (connect script,
    # build archive) was https://127.0.0.1:3000 and every deploy failed.
    # Port 3000 is bound to 127.0.0.1 only, so a request without the header
    # is the local agent/installer — never redirect it. Opt out entirely
    # with WOKKU_FORCE_SSL=0 for a plain-http or localhost-only deployment.
    if Rails.env.production? && ENV["WOKKU_FORCE_SSL"] != "0"
      config.force_ssl   = true
      config.ssl_options = { redirect: { exclude: LOCAL_CONTROL_REQUEST } }
    end

    if Rails.env.production?
      mail = WokkuHarness.mail_settings(ENV)
      # Mailer classes read these at load time (default from:), so set them
      # before eager loading; explicit MAIL_FROM* in .env still win.
      mail[:from_defaults].each { |k, v| ENV[k] ||= v }
      config.action_mailer.default_url_options = mail[:default_url_options]
      config.action_mailer.perform_deliveries  = mail[:perform_deliveries]
      config.action_mailer.delivery_method     = mail[:delivery_method]
      config.action_mailer.smtp_settings       = mail[:smtp_settings] if mail[:smtp_settings]
      unless mail[:perform_deliveries]
        config.after_initialize do
          Rails.logger.warn("wokku: no SMTP_ADDRESS set — emails (password reset, invites, alerts) are NOT sent. Add SMTP_* to .env.")
        end
      end
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
