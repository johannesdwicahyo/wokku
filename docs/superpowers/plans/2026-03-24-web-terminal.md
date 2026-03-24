# Web Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a browser-based terminal to the Wokku dashboard that lets users execute commands on their Dokku servers in real-time via xterm.js + ActionCable + SSH.

**Architecture:** The browser runs xterm.js inside a Stimulus controller. User keystrokes travel over an ActionCable WebSocket to a `TerminalChannel`, which opens a persistent SSH shell session to the target Dokku server via Net::SSH. SSH output streams back through ActionCable to xterm.js. The channel authenticates via Devise/Warden and authorizes via Pundit. Sessions auto-close after 15 minutes of inactivity.

**Tech Stack:** xterm.js 5.x (vendored), ActionCable (Solid Cable), Net::SSH (interactive shell), Stimulus controller, Tailwind CSS

---

## File Structure

### New Files

```
app/channels/terminal_channel.rb                  — ActionCable channel: auth, SSH shell, I/O forwarding
app/services/terminal_session.rb                   — Manages Net::SSH interactive shell lifecycle
app/javascript/controllers/terminal_controller.js  — Stimulus: xterm.js init, ActionCable subscription, I/O
vendor/javascript/xterm.js                         — Vendored xterm.js (ESM bundle)
vendor/javascript/xterm-addon-fit.js               — Vendored xterm-fit addon
vendor/javascript/xterm.css                        — xterm.js stylesheet
app/views/dashboard/terminals/show.html.erb        — Terminal page (server-level)
app/views/dashboard/apps/_terminal_tab.html.erb    — Terminal tab content for app detail
app/controllers/dashboard/terminals_controller.rb  — Serves terminal pages
test/channels/terminal_channel_test.rb
test/services/terminal_session_test.rb
```

### Modified Files

```
config/importmap.rb                                — Pin xterm.js and addon
app/views/layouts/dashboard.html.erb               — Include xterm.css stylesheet
app/views/dashboard/apps/show.html.erb             — Add "Terminal" tab
app/views/dashboard/servers/show.html.erb           — Add "Terminal" button
config/routes.rb                                   — Add terminal routes
```

---

## Task 1: Vendor xterm.js and Configure Import Map

**Files:**
- Create: `vendor/javascript/xterm.js`
- Create: `vendor/javascript/xterm-addon-fit.js`
- Create: `vendor/javascript/xterm.css`
- Modify: `config/importmap.rb`
- Modify: `app/views/layouts/dashboard.html.erb`

- [ ] **Step 1: Download xterm.js ESM bundles**

Download xterm.js v5.5.0 (latest stable) from CDN and vendor locally:

```bash
curl -o vendor/javascript/xterm.js "https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/+esm"
curl -o vendor/javascript/xterm-addon-fit.js "https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/+esm"
curl -o vendor/javascript/xterm.css "https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/css/xterm.min.css"
```

If CDN ESM bundles have issues, use importmap pins to CDN directly instead of vendoring.

- [ ] **Step 2: Pin in importmap**

Add to `config/importmap.rb`:

```ruby
pin "@xterm/xterm", to: "https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/+esm"
pin "@xterm/addon-fit", to: "https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/+esm"
```

- [ ] **Step 3: Add xterm.css to dashboard layout**

In `app/views/layouts/dashboard.html.erb`, inside `<head>` after the existing stylesheet link, add:

```erb
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@xterm/xterm@5.5.0/css/xterm.min.css">
```

- [ ] **Step 4: Commit**

```bash
git add config/importmap.rb app/views/layouts/dashboard.html.erb
git commit -m "feat: add xterm.js dependency for web terminal"
```

---

## Task 2: TerminalSession Service

**Files:**
- Create: `app/services/terminal_session.rb`
- Create: `test/services/terminal_session_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/services/terminal_session_test.rb
require "test_helper"

class TerminalSessionTest < ActiveSupport::TestCase
  test "initializes with server" do
    server = servers(:one)
    session = TerminalSession.new(server: server)
    assert_equal server, session.server
    assert_not session.connected?
  end

  test "builds ssh options from server" do
    server = servers(:one)
    session = TerminalSession.new(server: server)
    opts = session.send(:ssh_options)
    assert_equal server.port, opts[:port]
    assert opts[:non_interactive]
  end

  test "tracks last activity for timeout" do
    server = servers(:one)
    session = TerminalSession.new(server: server)
    session.touch!
    assert_in_delta Time.current.to_f, session.last_activity_at.to_f, 1.0
  end

  test "timed_out? returns true after inactivity" do
    server = servers(:one)
    session = TerminalSession.new(server: server, timeout: 1.second)
    session.touch!
    sleep 1.1
    assert session.timed_out?
  end
end
```

- [ ] **Step 2: Write the service**

```ruby
# app/services/terminal_session.rb
class TerminalSession
  attr_reader :server, :last_activity_at

  TIMEOUT = 15.minutes

  def initialize(server:, timeout: TIMEOUT)
    @server = server
    @timeout = timeout
    @ssh = nil
    @channel = nil
    @last_activity_at = Time.current
  end

  def connect!
    @ssh = Net::SSH.start(
      server.host,
      server.ssh_user || "dokku",
      ssh_options
    )
    @channel = @ssh.open_channel do |ch|
      ch.request_pty(term: "xterm-256color", chars_wide: 120, chars_high: 30) do |_ch, success|
        raise "Failed to get PTY" unless success
      end
      ch.send_channel_request("shell") do |_ch, success|
        raise "Failed to open shell" unless success
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
```

- [ ] **Step 3: Run tests**

Run: `bin/rails test test/services/terminal_session_test.rb`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add app/services/terminal_session.rb test/services/terminal_session_test.rb
git commit -m "feat: add TerminalSession service for SSH shell management"
```

---

## Task 3: TerminalChannel (ActionCable)

**Files:**
- Create: `app/channels/terminal_channel.rb`
- Create: `test/channels/terminal_channel_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/channels/terminal_channel_test.rb
require "test_helper"

class TerminalChannelTest < ActionCable::Channel::TestCase
  test "rejects subscription without server_id" do
    stub_connection current_user: users(:one)
    subscribe
    assert subscription.rejected?
  end

  test "rejects subscription for unauthorized server" do
    stub_connection current_user: users(:one)
    # Server belonging to another team would be unauthorized
    subscribe(server_id: -1)
    assert subscription.rejected?
  end
end
```

- [ ] **Step 2: Write the channel**

```ruby
# app/channels/terminal_channel.rb
class TerminalChannel < ApplicationCable::Channel
  PROCESS_INTERVAL = 0.05 # 50ms

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
        # broadcast_to is thread-safe (goes through pub/sub layer)
        ActionCable.server.broadcast(@stream_name, { type: "output", data: data.force_encoding("UTF-8") })
      end

      # Start background processing loop in a managed thread
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
    @thread&.join(5) # Wait up to 5 seconds for thread to finish
    @thread&.kill if @thread&.alive? # Force kill if still running
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
```

- [ ] **Step 3: Run tests**

Run: `bin/rails test test/channels/terminal_channel_test.rb`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add app/channels/terminal_channel.rb test/channels/terminal_channel_test.rb
git commit -m "feat: add TerminalChannel for real-time SSH shell over ActionCable"
```

---

## Task 4: Stimulus Terminal Controller (xterm.js)

**Files:**
- Create: `app/javascript/controllers/terminal_controller.js`

- [ ] **Step 1: Write the Stimulus controller**

```javascript
// app/javascript/controllers/terminal_controller.js
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"

export default class extends Controller {
  static values = {
    serverId: Number,
    appName: String // optional: scopes terminal to app context
  }
  static targets = ["container", "status"]

  connect() {
    this.initTerminal()
    this.connectChannel()
  }

  disconnect() {
    this.cleanup()
  }

  initTerminal() {
    this.term = new Terminal({
      cursorBlink: true,
      fontSize: 13,
      fontFamily: "'JetBrains Mono', monospace",
      theme: {
        background: "#0B1120",
        foreground: "#e2e8f0",
        cursor: "#22C55E",
        selectionBackground: "#334155",
        black: "#0B1120",
        red: "#ef4444",
        green: "#22C55E",
        yellow: "#eab308",
        blue: "#3b82f6",
        magenta: "#a855f7",
        cyan: "#06b6d4",
        white: "#e2e8f0",
        brightBlack: "#475569",
        brightRed: "#f87171",
        brightGreen: "#4ade80",
        brightYellow: "#facc15",
        brightBlue: "#60a5fa",
        brightMagenta: "#c084fc",
        brightCyan: "#22d3ee",
        brightWhite: "#f8fafc"
      },
      allowProposedApi: true
    })

    this.fitAddon = new FitAddon()
    this.term.loadAddon(this.fitAddon)
    this.term.open(this.containerTarget)
    this.fitAddon.fit()

    // Handle user input
    this.term.onData((data) => {
      if (this.subscription) {
        this.subscription.send({ type: "input", data: data })
      }
    })

    // Handle terminal resize
    this.resizeObserver = new ResizeObserver(() => {
      this.fitAddon.fit()
      if (this.subscription) {
        this.subscription.send({
          type: "resize",
          cols: this.term.cols,
          rows: this.term.rows
        })
      }
    })
    this.resizeObserver.observe(this.containerTarget)
  }

  connectChannel() {
    this.setStatus("connecting")
    this.consumer = createConsumer()

    this.subscription = this.consumer.subscriptions.create(
      { channel: "TerminalChannel", server_id: this.serverIdValue },
      {
        connected: () => {
          this.setStatus("connected")
          this.term.focus()

          // If scoped to an app, send initial command
          if (this.appNameValue) {
            setTimeout(() => {
              this.subscription.send({
                type: "input",
                data: `dokku enter ${this.appNameValue}\r`
              })
            }, 500)
          }
        },
        disconnected: () => {
          this.setStatus("disconnected")
          this.term.write("\r\n\x1b[33mDisconnected from server.\x1b[0m\r\n")
        },
        rejected: () => {
          this.setStatus("error")
          this.term.write("\r\n\x1b[31mConnection rejected. Check permissions.\x1b[0m\r\n")
        },
        received: (data) => {
          switch (data.type) {
            case "output":
              this.term.write(data.data)
              break
            case "error":
              this.term.write(`\r\n\x1b[31m${data.data}\x1b[0m\r\n`)
              this.setStatus("error")
              break
            case "disconnect":
              this.term.write(`\r\n\x1b[33m${data.reason}\x1b[0m\r\n`)
              this.setStatus("disconnected")
              break
          }
        }
      }
    )
  }

  setStatus(status) {
    if (!this.hasStatusTarget) return
    const colors = {
      connecting: "text-yellow-500",
      connected: "text-green-400",
      disconnected: "text-gray-500",
      error: "text-red-400"
    }
    const labels = {
      connecting: "Connecting...",
      connected: "Connected",
      disconnected: "Disconnected",
      error: "Error"
    }
    this.statusTarget.className = `text-xs font-mono ${colors[status] || "text-gray-500"}`
    this.statusTarget.textContent = labels[status] || status
  }

  reconnect() {
    this.cleanup()
    this.initTerminal()
    this.connectChannel()
  }

  cleanup() {
    this.resizeObserver?.disconnect()
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
    this.term?.dispose()
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/javascript/controllers/terminal_controller.js
git commit -m "feat: add terminal Stimulus controller with xterm.js integration"
```

---

## Task 5: Terminal Views and Routes

**Files:**
- Create: `app/controllers/dashboard/terminals_controller.rb`
- Create: `app/views/dashboard/terminals/show.html.erb`
- Create: `app/views/dashboard/apps/_terminal_tab.html.erb`
- Modify: `config/routes.rb`
- Modify: `app/views/dashboard/apps/show.html.erb`
- Modify: `app/views/dashboard/servers/show.html.erb`

- [ ] **Step 1: Write the terminals controller**

```ruby
# app/controllers/dashboard/terminals_controller.rb
module Dashboard
  class TerminalsController < BaseController
    def show
      @server = policy_scope(Server).find(params[:server_id])
      authorize @server, :show?
      @app = AppRecord.find_by(id: params[:app_id]) if params[:app_id]
    end
  end
end
```

- [ ] **Step 2: Add routes**

In `config/routes.rb`, inside `namespace :dashboard`, find the existing `resources :servers` block and add `resource :terminal` to it. **Preserve the existing `post :sync`**:

```ruby
resources :servers do
  member do
    post :sync
  end
  resource :terminal, only: [:show], controller: "terminals"
end
```

And inside the existing `resources :apps` block, add:

```ruby
resource :terminal, only: [:show], controller: "terminals"
```

**Important:** Read the file first and make surgical additions — do NOT rewrite the entire routes block.

- [ ] **Step 3: Write the terminal show view (server-level)**

```erb
<%# app/views/dashboard/terminals/show.html.erb %>
<% content_for(:title, "Terminal — #{@server.name}") %>

<div class="space-y-4">
  <div class="flex items-center justify-between">
    <div class="flex items-center space-x-3">
      <% if @app %>
        <%= link_to dashboard_app_path(@app), class: "text-sm text-gray-500 hover:text-gray-300 transition" do %>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>
        <% end %>
        <h1 class="text-lg font-semibold text-white font-mono"><%= @app.name %></h1>
        <span class="text-gray-600">on</span>
        <span class="text-sm text-gray-400 font-mono"><%= @server.name %></span>
      <% else %>
        <%= link_to dashboard_server_path(@server), class: "text-sm text-gray-500 hover:text-gray-300 transition" do %>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>
        <% end %>
        <h1 class="text-lg font-semibold text-white">Terminal</h1>
        <span class="text-sm text-gray-400 font-mono"><%= @server.name %> (<%= @server.host %>)</span>
      <% end %>
    </div>
    <div class="flex items-center space-x-3">
      <span data-terminal-target="status" class="text-xs font-mono text-yellow-500">Connecting...</span>
      <button data-action="click->terminal#reconnect" class="text-xs text-gray-500 hover:text-white transition px-2 py-1 rounded border border-[#334155] hover:border-[#475569]">Reconnect</button>
    </div>
  </div>

  <div class="rounded-xl border border-[#1E293B] bg-[#0B1120] overflow-hidden"
       data-controller="terminal"
       data-terminal-server-id-value="<%= @server.id %>"
       <%= "data-terminal-app-name-value=#{@app.name}" if @app %>>
    <div data-terminal-target="container" class="h-[calc(100vh-200px)] w-full"></div>
  </div>
</div>
```

- [ ] **Step 4: Add Terminal tab to app show page**

Read `app/views/dashboard/apps/show.html.erb`. Find the tab navigation section. Add a "Terminal" tab after "Metrics":

```erb
<%= link_to "Terminal", dashboard_app_terminal_path(@app), class: "..." %>
```

The tab should link to the terminal show page for that app's server, passing the app context.

- [ ] **Step 5: Add Terminal button to server show page**

Read `app/views/dashboard/servers/show.html.erb`. Add a "Terminal" button in the header area:

```erb
<%= link_to dashboard_server_terminal_path(@server), class: "inline-flex items-center px-3 py-1.5 bg-[#1E293B] border border-[#334155] text-gray-300 text-sm font-medium rounded-md hover:bg-[#334155] hover:text-white transition" do %>
  <svg class="w-4 h-4 mr-1.5" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v14a2 2 0 002 2z"/></svg>
  Terminal
<% end %>
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/dashboard/terminals_controller.rb app/views/dashboard/terminals/ config/routes.rb app/views/dashboard/apps/show.html.erb app/views/dashboard/servers/show.html.erb
git commit -m "feat: add terminal views, routes, and navigation tabs"
```

---

## Summary

| Task | Component | New Files | Modified Files |
|---|---|---|---|
| 1 | xterm.js dependency | 0 | 2 |
| 2 | TerminalSession service | 2 | 0 |
| 3 | TerminalChannel (ActionCable) | 2 | 0 |
| 4 | Stimulus terminal controller | 1 | 0 |
| 5 | Views, routes, navigation | 3 | 3 |

**Total: 8 new files, 5 modified files, 5 tasks**
