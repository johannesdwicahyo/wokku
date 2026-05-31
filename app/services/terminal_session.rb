require "shellwords"

# SSH terminal session -- wraps Net::SSH for dashboard and CLI use.
#
# Security: Shellwords.escape is used throughout build_command to prevent
# injection; the raw SSH exec interface (Net::SSH ch.exec) is used, NOT a
# local shell, so there is no additional shell-interpolation layer on the
# client side.
#
# Modes:
#   :shell      -- open an interactive dokku shell (admin-only via ACL)
#   :enter      -- `dokku enter <app> web` (no /bin/sh wrapper; PTY stdout fix)
#   :exec       -- `dokku run <app> <argv...>` (one-off container; like heroku run)
#   :db_connect -- `dokku <db_kind>:connect <name>`
#
# :exec uses `dokku run` rather than `dokku enter ... --`. Testing confirmed
# that `enter -- <cmd>` has the same broken-stdout bug as the wrapped enter
# case. `dokku run` spawns a fresh one-off container (does not exec into the
# running one), but output propagates correctly through the PTY and exit codes
# are preserved. This matches the Heroku `heroku run` mental model.
class TerminalSession
  attr_reader :server, :last_activity_at, :mode, :target, :exit_code

  TIMEOUT = 15.minutes
  MODES = %i[shell enter exec db_connect].freeze

  def initialize(server:, mode: :shell, target: nil, argv: [], db_kind: nil, timeout: TIMEOUT, app_name: nil)
    # Deprecated backward-compat alias: app_name: maps to mode: :enter, target: app_name
    if app_name
      if mode != :shell
        raise ArgumentError, "app_name: is deprecated; do not combine with mode:"
      end
      warn "[DEPRECATION] TerminalSession: app_name: keyword is deprecated; pass mode: :enter, target: <name> instead"
      mode = :enter
      target = app_name
    end

    raise ArgumentError, "Unknown mode: #{mode.inspect}. Must be one of #{MODES.inspect}" unless MODES.include?(mode)
    raise ArgumentError, "target is required for mode #{mode.inspect}" if mode != :shell && target.nil?

    @server = server
    @mode = mode
    @target = target
    @argv = argv
    @db_kind = db_kind
    @timeout = timeout
    @ssh = nil
    @channel = nil
    @exit_code = nil
    @on_exit = nil
    @last_activity_at = Time.current
  end

  def on_exit(&block)
    @on_exit = block
  end

  def connect!
    @ssh = Net::SSH.start(server.host, server.ssh_user || "dokku", ssh_options)
    @channel = @ssh.open_channel do |ch|
      ch.request_pty(term: "xterm-256color", chars_wide: 120, chars_high: 30) do |_ch, success|
        raise "Failed to get PTY" unless success
      end

      ch.on_request("exit-status") do |_c, data|
        @exit_code = data.read_long
        @on_exit&.call(@exit_code)
      end

      if @mode == :shell
        # Server terminal: dokku shell for admins
        ch.send_channel_request("shell") do |_ch, success|
          raise "Failed to open shell" unless success
        end
      else
        # App console / exec / db_connect: run a specific dokku command.
        # The dokku SSH wrapper prepends 'dokku' to whatever we exec.
        ch.exec(build_command) do |_ch, success|
          raise "Failed to exec command" unless success
        end
      end
    end
    touch!
    self
  end

  def connected?
    @ssh&.closed? == false && @channel&.active?
  rescue
    false
  end

  def send_data(data)
    return unless connected?
    touch!
    @channel.send_data(data)
    # NOTE: do NOT call @ssh.process here -- process_loop is the sole owner of
    # SSH I/O. Concurrent process calls are not thread-safe in Net::SSH.
  end

  def on_output(&block)
    return unless @channel
    @channel.on_data { |_, data| block.call(data) }
    @channel.on_extended_data { |_, _, data| block.call(data) }
  end

  def process(timeout = 0.01)
    return unless @ssh && !@ssh.closed?
    @ssh.process(timeout)
  rescue IOError, Net::SSH::Disconnect
    disconnect!
  end

  def resize(cols, rows)
    return unless @channel
    @channel.send_channel_request("window-change", :long, cols, :long, rows, :long, 0, :long, 0)
  rescue => e
    Rails.logger.debug("TerminalSession: resize failed: #{e.message}")
  end

  def disconnect!
    @channel&.close rescue nil
    @ssh&.close rescue nil
    @ssh = nil
    @channel = nil
  end

  def touch!
    @last_activity_at = Time.current
  end

  def timed_out?
    Time.current - @last_activity_at > @timeout
  end

  private

  def build_command
    case @mode
    when :enter
      # No /bin/sh wrapper. The wrapper caused PTY stdout to be lost because
      # the inner shell inherited the container main process's stdout (piped to
      # dokku's log driver). Let dokku's default shell selection handle it.
      # Trade-off: Alpine images without /bin/bash surface dokku's own error
      # rather than a /bin/sh fallback.
      "enter #{Shellwords.escape(@target)} web"
    when :exec
      raise ArgumentError, "exec mode requires non-empty argv" if @argv.empty?
      # Each argument is individually Shellwords-escaped, then joined with
      # spaces. This is the standard safe argv-style form for Net::SSH exec
      # (no extra shell layer on the client side).
      joined = @argv.map { |a| Shellwords.escape(a) }.join(" ")
      "run #{Shellwords.escape(@target)} #{joined}"
    when :db_connect
      raise ArgumentError, "db_connect requires db_kind" if @db_kind.to_s.empty?
      "#{Shellwords.escape(@db_kind)}:connect #{Shellwords.escape(@target)}"
    else
      raise ArgumentError, "build_command not implemented for mode #{@mode.inspect}"
    end
  end

  def ssh_options
    opts = {
      port: server.port || 22,
      non_interactive: true,
      timeout: 10
    }
    opts[:key_data] = [ server.ssh_private_key ] if server.ssh_private_key.present?
    opts
  end
end
