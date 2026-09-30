module Hosts
  # Generic host-SSH transport to a host: run_raw, run_raw_streaming, the
  # error classes, and the SSH plumbing. This is the ONLY raw command
  # transport in the app (W7 Phase 4: the dokku wrapper layer it was
  # extracted from is deleted); higher-level host mutations go through
  # wokkud typed ops (LifecycleOp/ServiceOp), not ad-hoc SSH.
  class Ssh
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

    # The platform's SSH login on app hosts (Wokku.config.host_ssh_user,
    # default root). Every raw host-SSH site reads this, never a literal.
    def self.user = Wokku.config.host_ssh_user

    # Non-root users reach root-only ops via `sudo -n` host helpers.
    def self.root_user? = user == "root"

    def initialize(server)
      @server = server
    end

    # Executes `command` verbatim as the platform host user (Ssh.user) —
    # no dokku-wire wrapping, no dependence on `@server.ssh_user` (the
    # "dokku" user has a forced command, so raw `docker ...` is unreachable
    # through it).
    def run_raw(command, timeout: 30, stdin: nil)
      output, error, exit_code = execute_over_ssh(self.class.user, command, display_command: command, timeout: timeout, stdin: stdin)
      raise_on_failure!(command, exit_code, error)
      output.strip
    end

    # Host user + verbatim + streaming. Streams stdout (+ stderr when
    # include_stderr, the default) line by line through &block, captures the
    # remote exit-status and raises CommandError if non-zero — tar failing
    # mid-export must not look like a clean stream.
    # include_stderr: false keeps stderr OUT of the yielded stream — required
    # for export/dump pipelines (mysqldump's password warning on stderr was
    # contaminating mysql backup dumps, making them unrestorable).
    # timeout: optional overall deadline in seconds (nil = no deadline) —
    # Timeout.timeout(nil) is a no-op wrapper, same mechanism
    # execute_over_ssh uses, so callers see the same TimeoutError either way.
    def run_raw_streaming(command, include_stderr: true, timeout: nil, &block)
      exit_code = nil
      stderr_tail = +""
      begin
        Timeout.timeout(timeout) do
          Net::SSH.start(@server.host, self.class.user, ssh_options) do |ssh|
            channel = ssh.open_channel do |ch|
              ch.exec(command) do |_ch, success|
                raise ConnectionError, "Failed to execute command" unless success

                ch.on_data { |_, data| block.call(data) }
                ch.on_extended_data { |_, _, data|
                  stderr_tail << data
                  stderr_tail.slice!(0, stderr_tail.length - 4096) if stderr_tail.length > 4096
                  block.call(data) if include_stderr
                }
                ch.on_request("exit-status") { |_, buf| exit_code = buf.read_long }
              end
            end
            channel.wait
          end
        end
      rescue Timeout::Error
        raise TimeoutError, "Host command timed out after #{timeout}s: #{command}"
      rescue Net::SSH::AuthenticationFailed => e
        @server.update_column(:status, Server.statuses[:auth_failed])
        raise ConnectionError, "SSH authentication failed: #{e.message}"
      rescue Net::SSH::Exception, SystemCallError, SocketError => e
        raise_connection_error!(e)
      end

      if exit_code && exit_code != 0
        raise CommandError.new(
          "Host command failed: #{command}\n#{stderr_tail}",
          exit_code: exit_code,
          stderr: stderr_tail
        )
      end
    end

    # Liveness probe: a bare no-op over the same transport.
    def connected?
      run_raw("true")
      true
    rescue ConnectionError, CommandError
      false
    end

    private

    # Shared SSH transport for the one-shot methods: opens a channel as
    # `ssh_user`, executes `wire_command` verbatim, and returns
    # [output, error, exit_code]. `display_command` is what shows up in
    # error messages when it differs from the wire command.
    def execute_over_ssh(ssh_user, wire_command, display_command:, timeout:, stdin: nil)
      output = ""
      error = ""
      exit_code = nil

      begin
        Timeout.timeout(timeout) do
          Net::SSH.start(@server.host, ssh_user, ssh_options) do |ssh|
            channel = ssh.open_channel do |ch|
              ch.exec(wire_command) do |_ch, success|
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
        raise TimeoutError, "Host command timed out after #{timeout}s: #{display_command}"
      rescue Net::SSH::AuthenticationFailed => e
        @server.update_column(:status, Server.statuses[:auth_failed])
        raise ConnectionError, "SSH authentication failed: #{e.message}"
      rescue Net::SSH::Exception, SystemCallError, SocketError => e
        raise_connection_error!(e)
      end

      [ output, error, exit_code ]
    end

    # Shared by every transport method: transient failures (host drops the
    # pre-auth connection under sshd MaxStartups pressure, network blips,
    # etc.) should never surface as a raw Net::SSH/SystemCallError/
    # SocketError — callers only know how to rescue ConnectionError.
    def raise_connection_error!(e)
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

    def raise_on_failure!(command, exit_code, error)
      return unless exit_code && exit_code != 0

      raise CommandError.new(
        "Host command failed: #{command}\n#{error}",
        exit_code: exit_code,
        stderr: error
      )
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
