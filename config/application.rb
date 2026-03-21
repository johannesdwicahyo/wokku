require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Wokku
  def self.ee?
    @ee = File.directory?(Rails.root.join("ee")) unless defined?(@ee)
    @ee
  end

  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Enterprise Edition autoloading
    if File.directory?(Rails.root.join("ee"))
      %w[app/models app/controllers app/policies app/services app/jobs app/mailers].each do |path|
        full = Rails.root.join("ee", path)
        if full.exist?
          config.autoload_paths << full.to_s
          config.eager_load_paths << full.to_s
        end
      end
      # Collapse concerns/ subdirectories so Zeitwerk doesn't namespace them
      Rails.autoloaders.main.collapse(Rails.root.join("ee/app/models/concerns").to_s)
      Rails.autoloaders.main.collapse(Rails.root.join("ee/app/controllers/concerns").to_s)
      config.paths["app/views"].unshift(Rails.root.join("ee/app/views").to_s)
      config.paths["db/migrate"] << Rails.root.join("ee/db/migrate").to_s if File.directory?(Rails.root.join("ee/db/migrate"))
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Active Record Encryption
    config.active_record.encryption.primary_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY", "QSNVYWnaiPjJZLuiLJpqltGrXF3OGlWT")
    config.active_record.encryption.deterministic_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY", "1ai2RRYzg1bYsPRdbAHf3b6Hr509K46u")
    config.active_record.encryption.key_derivation_salt = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT", "GUAhoy89MyftEpwL4lTNnkWGxLiWClU9")
  end
end
