import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { status: String }

  connect() {
    if (["queued", "running", "processing", "pending"].includes(this.statusValue)) {
      this.timer = setInterval(() => this.refresh(), 5000)
    }
  }

  disconnect() {
    clearInterval(this.timer)
    this.request?.abort()
  }

  async refresh() {
    if (document.hidden || this.request) return
    this.request = new AbortController()
    try {
      const response = await fetch(window.location.href, {
        headers: { Accept: "application/json" }, signal: this.request.signal
      })
      if (!response.ok) return
      const data = await response.json()
      if (data.status !== this.statusValue) Turbo.visit(window.location.href, { action: "replace" })
    } catch (error) {
      // A later poll retries temporary network failures; leaving the page aborts the request.
    } finally {
      this.request = null
    }
  }
}
