class TerminalChannel < ApplicationCable::Channel
  PROCESS_INTERVAL = 0.05

  def subscribed
    @server = Server.find_by(id: params[:server_id])

    unless @server && authorized?
      reject
      return
    end

    @stream_name = "terminal_#{@server.id}_#{current_user.id}_#{SecureRandom.hex(4)}"
    stream_from @stream_name

    @session = TerminalSession.new(server: @server)
    @mutex = Mutex.new
    @running = true

    begin
      @session.connect!
      @session.on_output do |data|
        ActionCable.server.broadcast(@stream_name, { type: "output", data: data.force_encoding("UTF-8") })
      end

      @thread = Thread.new { process_loop }
    rescue => e
      ActionCable.server.broadcast(@stream_name, { type: "error", data: "Connection failed: #{e.message}" })
      reject
    end
  end

  def receive(data)
    @mutex.synchronize do
      return unless @session&.connected?

      case data["type"]
      when "input"
        @session.send_data(data["data"])
      when "resize"
        @session.resize(data["cols"].to_i, data["rows"].to_i)
      end
    end
  end

  def unsubscribed
    @mutex.synchronize { @running = false }
    @thread&.join(5)
    @thread&.kill if @thread&.alive?
    @session&.disconnect!
    @session = nil
  end

  private

  def authorized?
    current_user.team_memberships.exists?(team_id: @server.team_id)
  end

  def process_loop
    while @mutex.synchronize { @running } && @session&.connected?
      begin
        @session.process(PROCESS_INTERVAL)

        if @session.timed_out?
          ActionCable.server.broadcast(@stream_name, {
            type: "disconnect", reason: "Session timed out after 15 minutes of inactivity"
          })
          @session.disconnect!
          break
        end

        sleep(PROCESS_INTERVAL)
      rescue => e
        ActionCable.server.broadcast(@stream_name, { type: "error", data: "Session error: #{e.message}" })
        break
      end
    end
  end
end
