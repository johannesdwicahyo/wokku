import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"

export default class extends Controller {
  static values = {
    serverId: String,
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
      fontFamily: "'Geist Mono', ui-monospace, monospace",
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
        // Encode as base64 to safely transmit binary/control characters (UTF-8 safe)
        const bytes = new TextEncoder().encode(data)
        let binary = ""
        for (const b of bytes) binary += String.fromCharCode(b)
        this.subscription.send({ type: "stdin", data: btoa(binary) })
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

    this.subscription = this.consumer.subscriptions.create(
      params,
      {
        connected: () => {
          // Send start message once the WebSocket connection is established
          const mode = this.appNameValue ? "enter" : "shell"
          const target = this.appNameValue || null
          this.subscription.send({
            type: "start",
            mode,
            target,
            argv: [],
            cols: this.term.cols,
            rows: this.term.rows
          })
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
            case "ready":
              this.setStatus("connected")
              this.term.focus()
              break
            case "stdout": {
              // Decode base64 output, handling full UTF-8
              const binary = atob(data.data)
              const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0))
              this.term.write(new TextDecoder().decode(bytes))
              break
            }
            case "exit":
              this.term.write(`\r\n\x1b[33mProcess exited with code ${data.code}.\x1b[0m\r\n`)
              this.setStatus("disconnected")
              break
            case "error":
              this.term.write(`\r\n\x1b[31m${data.message}\x1b[0m\r\n`)
              this.setStatus("error")
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
