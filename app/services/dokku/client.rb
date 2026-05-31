module Dokku
  class Client
    class CommandError < StandardError
      attr_reader :exit_code, :stderr

      def initialize(message, exit_code: nil, stderr: nil)
        @exit_code = exit_code
        @stderr = stderr
        super(message)
      end
    end

    class ConnectionError < StandardError; end
    class TimeoutError < ConnectionError; end

    def initialize(server)
      @server = server
    end

    def run(command, timeout: 30, stdin: nil)
      output = ""
      error = ""
      exit_code = nil

      begin
        Timeout.timeout(timeout) do
          Net::SSH.start(@server.host, @server.ssh_user || "dokku", ssh_options) do |ssh|
            channel = ssh.open_channel do |ch|
              ch.exec(shell_command(command)) do |_ch, success|
                raise ConnectionError, "Failed to execute command" unless success

                ch.on_data { |_, data| output << data }
                ch.on_extended_data { |_, _, data| error << data }
                ch.on_request("exit-status") { |_, buf| exit_code = buf.read_long }

                if stdin
                  ch.send_data(stdin)
                  ch.eof!
                end
              end
            end
            channel.wait
          end
        end
      rescue Timeout::Error
        raise TimeoutError, "Dokku command timed out after #{timeout}s: #{command}"
      rescue Net::SSH::AuthenticationFailed => e
        @server.update_column(:status, Server.statuses[:auth_failed])
        raise ConnectionError, "SSH authentication failed: #{e.message}"
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError => e
        @server.update_column(:status, Server.statuses[:unreachable])
        if defined?(Sentry)
          Sentry.capture_exception(e, level: :warning, extra: {
            server_id: @server.id,
            host: @server.host,
            port: @server.port,
            errno: e.class.name
          })
        end
        raise ConnectionError, "Cannot connect to server: #{e.message}"
      end

      if exit_code && exit_code != 0
        raise CommandError.new(
          "Dokku command failed: #{command}\n#{error}",
          exit_code: exit_code,
          stderr: error
        )
      end

      output.strip
    end

    # Streams stdout + stderr line by line through &block. Captures the
    # remote exit-status and raises CommandError if non-zero, mirroring
    # run's contract — so callers can swap run -> run_streaming without
    # losing error detection.
    def run_streaming(command, &block)
      exit_code = nil
      stderr_tail = +""
      Net::SSH.start(@server.host, @server.ssh_user || "dokku", ssh_options) do |ssh|
        channel = ssh.open_channel do |ch|
          ch.exec(shell_command(command)) do |_ch, success|
            raise ConnectionError, "Failed to execute command" unless success

            ch.on_data { |_, data| block.call(data) }
            ch.on_extended_data { |_, _, data|
              stderr_tail << data
              stderr_tail.slice!(0, stderr_tail.length - 4096) if stderr_tail.length > 4096
              block.call(data)
            }
            ch.on_request("exit-status") { |_, buf| exit_code = buf.read_long }
          end
        end
        channel.wait
      end

      if exit_code && exit_code != 0
        raise CommandError.new(
          "Dokku command failed: #{command}\n#{stderr_tail}",
          exit_code: exit_code,
          stderr: stderr_tail
        )
      end
    end

    def connected?
      run("version")
      true
    rescue ConnectionError, CommandError
      false
    end

    private

    def shell_command(command)
      if (@server.ssh_user || "dokku") == "dokku"
        command
      else
        "dokku #{command}"
      end
    end

    def ssh_options
      opts = {
        port: @server.port || 22,
        non_interactive: true,
        # Healthy SSH handshake completes in <1s on a same-region host;
        # 5s is generous. Longer timeouts here turn a sshd MaxStartups
        # drop into 10s of head-of-line blocking on the worker thread,
        # which is how the queue clogged in May 2026.
        timeout: 5,
        keepalive: true,
        keepalive_interval: 15
      }

      if @server.ssh_private_key.present?
        opts[:key_data] = [ @server.ssh_private_key ]
      end

      opts
    end
  end
end
