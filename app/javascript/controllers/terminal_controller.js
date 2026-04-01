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
        background: "#0c0c1f",
        foreground: "#e2e0fc",
        cursor: "#c0c1ff",
        selectionBackground: "#333348",
        black: "#0c0c1f",
        red: "#ffb4ab",
        green: "#c0c1ff",
        yellow: "#ffb694",
        blue: "#d2bbff",
        magenta: "#c0c1ff",
        cyan: "#d2bbff",
        white: "#e2e0fc",
        brightBlack: "#4a4453",
        brightRed: "#ffb4ab",
        brightGreen: "#c0c1ff",
        brightYellow: "#ffb694",
        brightBlue: "#d2bbff",
        brightMagenta: "#c0c1ff",
        brightCyan: "#d2bbff",
        brightWhite: "#e2e0fc"
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

    const params = { channel: "TerminalChannel", server_id: this.serverIdValue }
    if (this.appNameValue) {
      params.app_name = this.appNameValue
    }

    this.subscription = this.consumer.subscriptions.create(
      params,
      {
        connected: () => {
          this.setStatus("connected")
          this.term.focus()
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
              if (!this._connected) {
                this._connected = true
                this.setStatus("connected")
              }
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
