require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Wokku
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.i18n.available_locales = [ :en, :id ]
    config.i18n.default_locale = :en

    # Use structure.sql so Postgres-specific objects (uuidv7() function,
    # custom indexes) survive db:schema:load.
    config.active_record.schema_format = :sql

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # IDR launch: all business-day boundaries (daily debit, "today so
    # far", activity timestamps) are Jakarta-local. Rails stores in UTC,
    # but reads and cron schedules run in this zone.
    config.time_zone = "Asia/Jakarta"
    # config.eager_load_paths << Rails.root.join("extras")

    # Active Record Encryption.
    # In production the three keys MUST come from the environment; hard-fail
    # on boot if any are missing. Dev/test keep weak committed defaults so
    # contributors can run bin/rails without extra setup — these are NOT safe
    # for production and should never encrypt real user data.
    ar_enc_key = ->(env_var, dev_default) do
      ENV.fetch(env_var) do
        # During asset precompile in Docker build, Rails sets
        # SECRET_KEY_BASE_DUMMY=1 to signal 'we're just compiling assets, no
        # real secrets yet.' Fall back to dev defaults in that phase too.
        if Rails.env.production? && !ENV["SECRET_KEY_BASE_DUMMY"]
          raise "#{env_var} must be set in production (see .kamal/secrets + config/deploy.yml env.secret)"
        else
          dev_default
        end
      end
    end
    config.active_record.encryption.primary_key          = ar_enc_key.call("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY",          "QSNVYWnaiPjJZLuiLJpqltGrXF3OGlWT")
    config.active_record.encryption.deterministic_key    = ar_enc_key.call("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY",    "1ai2RRYzg1bYsPRdbAHf3b6Hr509K46u")
    config.active_record.encryption.key_derivation_salt  = ar_enc_key.call("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT",  "GUAhoy89MyftEpwL4lTNnkWGxLiWClU9")
    # Tolerate reading plaintext rows while a column migration is rolling
    # out. Harmless after backfills complete; leave on so future column-
    # encryption migrations don't need a synchronised deploy + migration.
    config.active_record.encryption.support_unencrypted_data = true
  end
end
