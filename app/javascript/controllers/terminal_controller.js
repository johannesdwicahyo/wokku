import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"

export default class extends Controller {
  static values = {
    serverId: Number,
    appName: String
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

    this.term.onData((data) => {
      if (this.subscription) {
        this.subscription.send({ type: "input", data: data })
      }
    })

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
