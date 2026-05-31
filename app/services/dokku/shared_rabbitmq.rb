# frozen_string_literal: true

require "shellwords"

module Dokku
  # Thin wrapper around the `dokku-shared-rabbitmq` plugin. The plugin
  # creates a tenant user + per-tenant vhost on a shared RabbitMQ
  # container and emits an `amqp://<user>:<pw>@<host>:<port>/<vhost>` URL.
  class SharedRabbitmq
    class ParseError < StandardError; end

    def initialize(client)
      @client = client
    end

    # Returns { envs: { "RABBITMQ_URL" => "..." }, role:, vhost:, password: }
    def provision_tenant!(slug:)
      output = @client.run("shared-rabbitmq:create #{Shellwords.escape(slug)}", timeout: 60)
      parse_connection_url(output)
    end

    def destroy_tenant!(slug:)
      @client.run("shared-rabbitmq:destroy #{Shellwords.escape(slug)} -f", timeout: 60)
    rescue Dokku::Client::CommandError => e
      raise unless e.message.match?(/not found/i)
    end

    private

    def parse_connection_url(text)
      url = text.lines.map(&:strip).find { |l| l.start_with?("amqp://") }
      raise ParseError, "no connection URL in plugin output: #{text.inspect}" unless url
      uri = URI.parse(url)
      {
        envs: { "RABBITMQ_URL" => url },
        role: uri.user,
        vhost: uri.path.sub(%r{\A/}, ""),
        password: uri.password
      }
    end
  end
end
