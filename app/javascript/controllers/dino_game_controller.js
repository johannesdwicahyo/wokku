import { Controller } from "@hotwired/stimulus"

// Landing page easter egg — dino follows mouse, dies on meteor collision, click to revive.
//
// Usage:
//   <div data-controller="dino-game">
//     <div data-dino-game-target="dino" class="terminal-dino">🦕</div>
//   </div>
export default class extends Controller {
  static targets = ["dino"]

  connect() {
    this.alive = true
    this.lastX = null
    this.dinoEmoji = "🦕"
    this.graveEmoji = "🪦"
    this.dinoTarget.title = "Dodge the meteors!"

    this.onMouseMove = this.trackMouse.bind(this)
    document.addEventListener("mousemove", this.onMouseMove)
    this.collisionTimer = setInterval(() => this.checkCollisions(), 33)
  }

  disconnect() {
    document.removeEventListener("mousemove", this.onMouseMove)
    clearInterval(this.collisionTimer)
  }

  trackMouse(e) {
    if (!this.alive) return
    const rect = this.element.getBoundingClientRect()
    if (e.clientY < rect.top - 200 || e.clientY > rect.bottom + 100) return

    const relX = e.clientX - rect.left
    const pct = Math.max(2, Math.min(92, (relX / rect.width) * 100))
    this.dinoTarget.style.left = pct + "%"

    if (this.lastX === null) this.lastX = pct
    if (pct < this.lastX - 1) {
      this.dinoTarget.style.transform = "scaleX(-1)"
    } else if (pct > this.lastX + 1) {
      this.dinoTarget.style.transform = "scaleX(1)"
    }
    this.lastX = pct
  }

  checkCollisions() {
    if (!this.alive) return
    const dinoRect = this.dinoTarget.getBoundingClientRect()
    const dinoBox = {
      left: dinoRect.left + 4, right: dinoRect.right - 4,
      top: dinoRect.top + 4, bottom: dinoRect.bottom - 4
    }

    const meteors = document.querySelectorAll(".meteor")
    for (let i = 0; i < meteors.length; i++) {
      const m = meteors[i].getBoundingClientRect()
      const headY = m.bottom
      const headX = m.left + m.width / 2
      if (headX >= dinoBox.left && headX <= dinoBox.right &&
          headY >= dinoBox.top && headY <= dinoBox.bottom) {
        this.kill()
        return
      }
    }
  }

  kill() {
    this.alive = false
    this.dinoTarget.textContent = this.graveEmoji
    this.dinoTarget.classList.add("dead")
    this.dinoTarget.style.transform = "none"
    this.dinoTarget.style.animation = "dino-shake 0.3s ease-in-out"
    this.dinoTarget.title = "Click to revive!"
  }

  revive() {
    this.alive = true
    this.dinoTarget.textContent = this.dinoEmoji
    this.dinoTarget.classList.remove("dead")
    this.dinoTarget.title = "Dodge the meteors!"
  }
}
