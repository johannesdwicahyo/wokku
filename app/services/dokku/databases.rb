require "shellwords"

module Dokku
  class Databases
    SUPPORTED_TYPES = %w[postgres redis mysql mongodb memcached rabbitmq elasticsearch mariadb meilisearch clickhouse nats].freeze

    # Map internal type names to Dokku plugin command names
    DOKKU_PLUGIN_NAME = {
      "mongodb" => "mongo"
    }.freeze

    def initialize(client)
      @client = client
    end

    def list(service_type)
      validate_type!(service_type)
      output = @client.run("#{plugin_name(service_type)}:list")
      output.lines.map(&:strip).reject { |l| l.start_with?("=") || l.blank? }
    end

    # `image:` lets a tier override the default postgres / mysql / etc.
    # Docker image — used for pgvector, postgis, timescaledb flavours
    # where the extension binary ships in the image. Dokku's plugin
    # `<plugin>:create --image <name> --image-version <tag>` does the
    # right thing; nil values fall through to the plugin's default.
    def create(service_type, name, image: nil, image_version: nil)
      validate_type!(service_type)
      flags = []
      flags << "--image #{Shellwords.escape(image)}"                 if image.present?
      flags << "--image-version #{Shellwords.escape(image_version)}" if image_version.present?
      cmd = "#{plugin_name(service_type)}:create #{Shellwords.escape(name)}"
      cmd = "#{cmd} #{flags.join(' ')}" if flags.any?
      @client.run(cmd)
    end

    def destroy(service_type, name)
      validate_type!(service_type)
      @client.run("#{plugin_name(service_type)}:destroy #{Shellwords.escape(name)} --force")
    end

    def info(service_type, name)
      validate_type!(service_type)
      output = @client.run("#{plugin_name(service_type)}:info #{Shellwords.escape(name)}")
      parse_report(output)
    end

    def link(service_type, db_name, app_name)
      validate_type!(service_type)
      @client.run("#{plugin_name(service_type)}:link #{Shellwords.escape(db_name)} #{Shellwords.escape(app_name)}")
    end

    def unlink(service_type, db_name, app_name)
      validate_type!(service_type)
      @client.run("#{plugin_name(service_type)}:unlink #{Shellwords.escape(db_name)} #{Shellwords.escape(app_name)}")
    end

    private

    def plugin_name(service_type)
      DOKKU_PLUGIN_NAME[service_type] || service_type
    end

    def validate_type!(type)
      raise ArgumentError, "Unsupported service type: #{type}" unless SUPPORTED_TYPES.include?(type)
    end

    def parse_report(output)
      result = {}
      output.each_line do |line|
        next if line.strip.blank? || line.start_with?("=")
        key, value = line.split(":", 2).map(&:strip)
        result[key.to_s.parameterize(separator: "_")] = value if key
      end
      result
    end
  end
end
