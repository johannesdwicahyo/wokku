module Dokku
  class Databases
    SUPPORTED_TYPES = %w[postgres redis mysql mongodb memcached rabbitmq].freeze

    def initialize(client)
      @client = client
    end

    def list(service_type)
      validate_type!(service_type)
      output = @client.run("#{service_type}:list")
      output.lines.map(&:strip).reject { |l| l.start_with?("=") || l.blank? }
    end

    def create(service_type, name)
      validate_type!(service_type)
      @client.run("#{service_type}:create #{name}")
    end

    def destroy(service_type, name)
      validate_type!(service_type)
      @client.run("#{service_type}:destroy #{name} --force")
    end

    def info(service_type, name)
      validate_type!(service_type)
      output = @client.run("#{service_type}:info #{name}")
      parse_report(output)
    end

    def link(service_type, db_name, app_name)
      validate_type!(service_type)
      @client.run("#{service_type}:link #{db_name} #{app_name}")
    end

    def unlink(service_type, db_name, app_name)
      validate_type!(service_type)
      @client.run("#{service_type}:unlink #{db_name} #{app_name}")
    end

    private

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
