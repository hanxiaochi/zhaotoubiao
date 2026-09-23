import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// DOM dialog keeps the confirmation visible, keyboard-accessible and testable.
// No action is submitted until the user explicitly accepts this specific prompt.
export default class extends Controller {
  static targets = ["message", "cancel"]

  connect() {
    this.previousConfirm = Turbo.config.forms.confirm
    this.handler = message => this.request(message)
    Turbo.config.forms.confirm = this.handler
    this.beforeCache = () => this.finish(false)
    document.addEventListener("turbo:before-cache", this.beforeCache)
  }

  disconnect() {
    this.finish(false)
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    if (Turbo.config.forms.confirm === this.handler) Turbo.config.forms.confirm = this.previousConfirm
  }

  request(message) {
    if (this.resolve) return Promise.resolve(false)
    this.opener = document.activeElement
    this.messageTarget.textContent = message
    return new Promise(resolve => {
      this.resolve = resolve
      this.element.showModal()
      this.cancelTarget.focus()
    })
  }

  accept() { this.finish(true) }

  cancel(event) {
    event?.preventDefault()
    this.finish(false)
  }

  closed() {
    if (!this.element.open) this.finish(false)
  }

  finish(accepted) {
    if (!this.resolve) return
    const resolve = this.resolve
    this.resolve = null
    this.element.close()
    if (this.opener?.isConnected) this.opener.focus()
    resolve(accepted)
  }
}
