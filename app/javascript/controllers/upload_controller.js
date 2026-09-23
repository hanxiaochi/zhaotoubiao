import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["progress", "status", "cancel", "submit"]

  disconnect() {
    this.request?.abort()
  }

  submit(event) {
    if (!window.XMLHttpRequest || !window.FormData) return
    event.preventDefault()
    if (this.request || !this.element.reportValidity()) return
    const request = new XMLHttpRequest()
    this.request = request
    this.submitTarget.disabled = true
    this.cancelTarget.hidden = false
    this.progressTarget.hidden = false
    this.progressTarget.value = 0
    this.statusTarget.textContent = "开始传输文件…"
    request.open("POST", this.element.action)
    request.responseType = "json"
    request.timeout = 300000
    request.setRequestHeader("Accept", "application/json")
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (token) request.setRequestHeader("X-CSRF-Token", token)
    request.upload.onprogress = (progress) => {
      if (!progress.lengthComputable) {
        this.progressTarget.removeAttribute("value")
        this.statusTarget.textContent = "正在传输文件，大小未知…"
        return
      }
      const percent = Math.min(100, Math.floor(progress.loaded / progress.total * 100))
      this.progressTarget.value = percent
      this.statusTarget.textContent = percent === 100 ? "传输100%，服务器正在校验与保存，请勿重复提交…" : `正在传输 ${percent}%`
    }
    request.onload = () => {
      if (request.status === 201 && request.response?.redirect_url) {
        const destination = new URL(request.response.redirect_url, window.location.origin)
        if (destination.origin === window.location.origin) {
          this.finish("文件已保存，正在打开详情…")
          Turbo.visit(destination.href)
          return
        }
      }
      const errors = request.response?.errors
      this.finish(Array.isArray(errors) ? errors.join("；") : "未能确认上传结果。请检查登录状态和项目台账后再重试。")
    }
    request.onerror = () => this.finish("网络中断，结果未确认。请先检查项目台账，避免重复提交。")
    request.ontimeout = () => this.finish("上传响应超时。请先检查项目台账，确认未保存后再重试。")
    request.onabort = () => this.finish("已取消传输；若传输已完成，请先检查台账是否已保存。")
    request.send(new FormData(this.element))
  }

  cancel() {
    this.request?.abort()
  }

  finish(message) {
    this.request = null
    this.submitTarget.disabled = false
    this.cancelTarget.hidden = true
    this.statusTarget.textContent = message
  }
}
