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
#   :db_connect -- docker exec into the wokkud-managed DB container with the engine client
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
    @ssh = Net::SSH.start(server.host, ssh_user, ssh_options)
    if db_target?
      resolve_db_service!
    elsif swarm_target?
      resolve_swarm_container!
      probe_swarm_shell! if @mode == :enter
    elsif @mode == :enter
      probe_shell!
    end
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

  # B6 W4: flagged/native apps run as Swarm tasks — `dokku enter`/`dokku run`
  # target the STOPPED dokku container (or none for native apps). Their
  # sessions connect as root and docker-exec into the live task container:
  # :enter gets an interactive shell; :exec runs argv inside the running
  # task (heroku-run-alike; a fresh one-off container would need env on the
  # command line — secrets in `ps` — so exec-into-running is the v1 shape).
  def swarm_target?
    return false unless %i[enter exec].include?(@mode)
    @swarm_target ||= AppRecord.find_by(name: @target, server: @server)
      &.then { |a| a.wokkud_lifecycle? || a.wokkud_native? } || false
  end

  def db_target? = @mode == :db_connect

  def ssh_user
    (db_target? || swarm_target?) ? "root" : (server.ssh_user || "dokku")
  end

  def resolve_swarm_container!
    names = @ssh.exec!("docker ps --format '{{.Names}}'").to_s.split("\n")
    @swarm_container = names.find { |n| n.match?(/\Awokku-#{Regexp.escape(@target)}-web\.\d+\./) }
    raise "No running task for #{@target} — is the app deployed and running?" unless @swarm_container
  end

  def probe_swarm_shell!
    out = @ssh.exec!(
      "docker exec #{Shellwords.escape(@swarm_container)} /bin/sh -c 'test -x /bin/bash && echo bash || echo sh'"
    ).to_s.strip
    @shell_binary = out == "sh" ? :sh : :bash
  rescue => e
    Rails.logger.debug("TerminalSession: swarm shell probe failed (#{e.class}: #{e.message}); defaulting to :bash")
    @shell_binary = :bash
  end

  # W7: all DB services are wokkud-managed containers — db_connect execs the
  # engine client inside the service container. DEDICATED services only: a
  # shared row's container is the multi-tenant parent, and `docker exec`ing a
  # client into it means either a superuser session (postgres) or no working
  # auth at all (redis ACL users aren't provisioned for interactive exec) —
  # both unacceptable. The DatabaseService ROW is authoritative for
  # engine/container/db/creds; the client-supplied db_kind is only a
  # cross-check.
  def resolve_db_service!
    @db_service = DatabaseService.find_by(name: @target, server: @server)
    raise "Unknown database #{@target} on #{@server.name}" unless @db_service
    if @db_service.shared?
      raise ArgumentError,
        "shared-tenant console is not yet supported — connect with the addon's DSN from your app, or upgrade to dedicated"
    end
    validate_db_kind!

    names = @ssh.exec!("docker ps --format '{{.Names}}'").to_s.split("\n")
    @db_container = names.find { |n| n == @db_service.container_name }
    raise "Database container #{@db_service.container_name} is not running" unless @db_container
  end

  def validate_db_kind!
    return if @db_kind.to_s.empty? || @db_kind.to_s == @db_service.service_type
    raise ArgumentError, "db_kind mismatch: got #{@db_kind}, service is #{@db_service.service_type}"
  end

  def db_connect_command
    c  = Shellwords.escape(@db_container)
    db = Shellwords.escape(@db_service.dedicated_db_name)
    pw = @db_service.dsn.presence && URI.parse(@db_service.dsn).password

    case @db_service.service_type
    when "postgres"
      "docker exec -it #{c} psql -U postgres -d #{db}"
    when "mariadb", "mysql"
      client = @db_service.service_type == "mariadb" ? "mariadb" : "mysql"
      # MYSQL_PWD rides docker exec -e: visible in root's host ps only, never
      # in the container argv — same exposure dokku's own :connect had.
      "docker exec -it -e MYSQL_PWD=#{Shellwords.escape(pw.to_s)} #{c} #{client} -uroot #{db}"
    when "mongodb"
      "docker exec -it #{c} mongosh -u root -p #{Shellwords.escape(pw.to_s)} --authenticationDatabase admin #{db}"
    when "redis"
      base = "docker exec -it #{c} redis-cli"
      pw.present? ? "#{base} --no-auth-warning -a #{Shellwords.escape(pw)}" : base
    else
      raise ArgumentError, "no interactive client for #{@db_service.service_type}"
    end
  end

  def build_command
    return db_connect_command if db_target?

    if swarm_target?
      case @mode
      when :enter
        shell = @shell_binary == :sh ? "/bin/sh" : "/bin/bash"
        return "docker exec -it #{Shellwords.escape(@swarm_container)} #{shell}"
      when :exec
        raise ArgumentError, "exec mode requires non-empty argv" if @argv.empty?
        joined = @argv.map { |a| Shellwords.escape(a) }.join(" ")
        return "docker exec -i #{Shellwords.escape(@swarm_container)} #{joined}"
      end
    end

    case @mode
    when :enter
      # Per-image shell selection (backlog 4.4):
      # - Default `dokku enter APP web` lets dokku pick /bin/bash, which
      #   works on Debian/Ruby/Node base images. Wrapping in
      #   `/bin/sh -c 'exec /bin/bash || exec /bin/sh'` silently kills
      #   PTY stdout on those images, so we MUST NOT wrap.
      # - Alpine / distroless images don't ship /bin/bash; we detect
      #   this with a cheap pre-flight probe in `probe_shell!` and pass
      #   `/bin/sh` explicitly here so dokku enter doesn't crash with
      #   `exec: "/bin/bash": stat /bin/bash: no such file or directory`.
      base = "enter #{Shellwords.escape(@target)} web"
      @shell_binary == :sh ? "#{base} /bin/sh" : base
    when :exec
      raise ArgumentError, "exec mode requires non-empty argv" if @argv.empty?
      # Each argument is individually Shellwords-escaped, then joined with
      # spaces. This is the standard safe argv-style form for Net::SSH exec
      # (no extra shell layer on the client side).
      joined = @argv.map { |a| Shellwords.escape(a) }.join(" ")
      "run #{Shellwords.escape(@target)} #{joined}"
    else
      raise ArgumentError, "build_command not implemented for mode #{@mode.inspect}"
    end
  end

  # Detect whether the target app's running container has /bin/bash.
  # Sets @shell_binary to :bash (default — dokku enter picks bash) or
  # :sh (we explicitly pass /bin/sh as the entry binary).
  #
  # Implementation: non-PTY synchronous exec via Net::SSH#exec!. The
  # PTY-stdout-loss bug with `dokku enter -- cmd` only manifests when a
  # PTY is allocated; for a one-shot test command without a PTY the
  # output is captured cleanly. Round-trip ~700ms on jkt-01.
  #
  # Cached in Rails.cache for 30 minutes keyed by server + app target,
  # so subsequent terminal opens skip the probe entirely (~5ms vs
  # 700ms). Trade-off: a base-image swap (e.g. Debian → Alpine in a
  # Dockerfile rewrite) takes up to 30 min to be recognized; users
  # would see one failed open with a bash-not-found error, then it
  # self-corrects on the next attempt after TTL expires. Rare enough
  # to not warrant an explicit cache-bust on deploy.
  #
  # Fail-open: if anything goes wrong, default to :bash and let dokku
  # surface its own error. Never block the connection on the probe.
  PROBE_CACHE_TTL = 30.minutes

  def probe_shell!
    cached = Rails.cache.read(probe_cache_key)
    if cached
      @shell_binary = cached.to_sym
      return
    end

    cmd = "enter #{Shellwords.escape(@target)} web -- /bin/sh -c " \
          "#{Shellwords.escape("test -x /bin/bash && echo bash || echo sh")}"
    output = @ssh.exec!(cmd).to_s.strip
    @shell_binary = output == "sh" ? :sh : :bash
    Rails.cache.write(probe_cache_key, @shell_binary.to_s, expires_in: PROBE_CACHE_TTL)
  rescue => e
    Rails.logger.debug("TerminalSession: shell probe failed (#{e.class}: #{e.message}); defaulting to :bash")
    @shell_binary = :bash
  end

  def probe_cache_key
    "terminal_shell:#{server.id}:#{@target}"
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
