module Git
  class Server
    def initialize(host: "0.0.0.0", port: 2222)
      @host = host
      @port = port
    end

    def start
      require "socket"

      server = TCPServer.new(@host, @port)
      Rails.logger.info("Git SSH server listening on #{@host}:#{@port}")

      loop do
        Thread.start(server.accept) do |client|
          handle_connection(client)
        end
      end
    end

    private

    def handle_connection(client)
      # In production, this would use sshd with AuthorizedKeysCommand
      # For now, this is a placeholder for the TCP connection handler
      client.close
    rescue StandardError => e
      Rails.logger.error("Git server error: #{e.message}")
      client&.close
    end
  end
end
