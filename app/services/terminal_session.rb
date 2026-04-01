class TerminalSession
  attr_reader :server, :last_activity_at

  TIMEOUT = 15.minutes

  def initialize(server:, app_name: nil, timeout: TIMEOUT)
    @server = server
    @app_name = app_name
    @timeout = timeout
    @ssh = nil
    @channel = nil
    @last_activity_at = Time.current
  end

  def connect!
    if @app_name
      # App console: SSH as deploy user, docker exec into the container
      @ssh = Net::SSH.start(server.host, "deploy", ssh_options)
      container = "#{@app_name}.web.1"
      @channel = @ssh.open_channel do |ch|
        ch.request_pty(term: "xterm-256color", chars_wide: 120, chars_high: 30) do |_ch, success|
          raise "Failed to get PTY" unless success
        end
        ch.exec("docker exec -i #{container} /bin/bash 2>/dev/null || docker exec -i #{container} /bin/sh") do |_ch, success|
          raise "Failed to enter container" unless success
        end
      end
    else
      # Server terminal: SSH as dokku user, get Dokku shell
      @ssh = Net::SSH.start(server.host, server.ssh_user || "dokku", ssh_options)
      @channel = @ssh.open_channel do |ch|
        ch.request_pty(term: "xterm-256color", chars_wide: 120, chars_high: 30) do |_ch, success|
          raise "Failed to get PTY" unless success
        end
        ch.send_channel_request("shell") do |_ch, success|
          raise "Failed to open shell" unless success
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
    @ssh.process(0.01)
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

  def ssh_options
    opts = {
      port: server.port || 22,
      non_interactive: true,
      timeout: 10
    }
    opts[:key_data] = [server.ssh_private_key] if server.ssh_private_key.present?
    opts
  end
end
