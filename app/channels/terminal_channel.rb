require "base64"

class TerminalChannel < ApplicationCable::Channel
  PROCESS_INTERVAL = 0.05
  ALLOWED_MODES = %w[shell enter exec db_connect].freeze

  def subscribed
    @server = Server.find_by(id: params[:server_id])
    unless @server && current_user && ServerPolicy.new(current_user, @server).show?
      reject
      return
    end

    @stream_name = "terminal_#{@server.id}_#{current_user.id}_#{SecureRandom.hex(4)}"
    stream_from @stream_name
    @mutex = Mutex.new
    @running = true
    @started = false
  end

  def receive(data)
    case data["type"]
    when "start"  then handle_start(data)
    when "stdin"  then handle_stdin(data)
    when "resize" then handle_resize(data)
    when "signal" then handle_signal(data)
    end
  end

  def unsubscribed
    return unless @mutex

    @mutex.synchronize { @running = false }
    @thread&.join(5)
    @thread&.kill if @thread&.alive?
    @session&.disconnect!
    @session = nil
  end

  private

  def emit(payload)
    ActionCable.server.broadcast(@stream_name, payload)
  end

  def handle_start(data)
    already_started = @mutex.synchronize do
      if @started
        true
      else
        @started = true
        false
      end
    end
    return emit({ type: "error", message: "already started" }) if already_started

    mode = data["mode"].to_s
    return emit({ type: "error", message: "unknown mode" }) unless ALLOWED_MODES.include?(mode)

    target = data["target"].to_s
    argv = Array(data["argv"]).map(&:to_s)
    db_kind = nil

    case mode
    when "shell"
      unless ServerPolicy.new(current_user, @server).admin_terminal?
        return emit({ type: "error", message: "shell mode requires admin role" })
      end
    when "enter", "exec"
      return emit({ type: "error", message: "target required" }) if target.empty?
      app = policy_scope(AppRecord).find_by(name: target, server_id: @server.id)
      return emit({ type: "error", message: "app not found or access denied" }) unless app
    when "db_connect"
      return emit({ type: "error", message: "target required" }) if target.empty?
      db = policy_scope(DatabaseService).find_by(name: target, server_id: @server.id)
      return emit({ type: "error", message: "database not found or access denied" }) unless db
      db_kind = db.service_type
    end

    @session = TerminalSession.new(
      server: @server, mode: mode.to_sym,
      target: mode == "shell" ? nil : target, argv: argv, db_kind: db_kind
    )

    begin
      @session.connect!
    rescue => e
      emit({ type: "error", message: "spawn failed: #{e.message}" })
      return
    end

    @session.on_output { |bytes| emit({ type: "stdout", data: Base64.strict_encode64(bytes) }) }
    @session.on_exit { |code| emit({ type: "exit", code: code.to_i }) }

    emit({ type: "ready" })

    if @server.team
      Activity.log(
        user: current_user,
        team: @server.team,
        action: "terminal.start",
        metadata: { mode: mode, target: target.presence }
      )
    end

    @thread = Thread.new { process_loop }
  end

  def handle_stdin(data)
    @mutex.synchronize do
      return unless @session&.connected?

      @session.send_data(Base64.decode64(data["data"].to_s))
    end
  end

  def handle_resize(data)
    @mutex.synchronize do
      return unless @session

      @session.resize(data["cols"].to_i, data["rows"].to_i)
    end
  end

  def handle_signal(data)
    @mutex.synchronize do
      return unless @session&.connected?

      # Forward INT as a Ctrl-C byte -- covers the common case without needing
      # a full SSH "signal" channel request.
      @session.send_data("\x03") if data["signal"] == "INT"
    end
  end

  def process_loop
    while @mutex.synchronize { @running } && @session&.connected?
      begin
        # Net::SSH::Connection::Session#process already blocks up to its
        # timeout argument waiting for I/O, so we don't need an explicit
        # sleep between iterations. Removing the sleep cuts perceived PTY
        # output latency roughly in half (~50ms vs ~100ms).
        @session.process(PROCESS_INTERVAL)

        if @session.timed_out?
          emit({ type: "error", message: "session timed out after 15 minutes of inactivity" })
          @session.disconnect!
          break
        end
      rescue => e
        emit({ type: "error", message: "session error: #{e.message}" })
        break
      end
    end
  end

  def policy_scope(klass)
    Pundit.policy_scope!(current_user, klass)
  end
end
