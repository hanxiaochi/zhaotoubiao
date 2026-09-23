import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "panel"]

  connect() {
    this.select("all")
  }

  filter(event) {
    this.select(event.currentTarget.dataset.group)
  }

  select(group) {
    this.element.classList.toggle("workspace-filtered", group !== "all")
    this.buttonTargets.forEach(button => {
      button.setAttribute("aria-pressed", String(button.dataset.group === group))
    })
    this.panelTargets.forEach(panel => {
      panel.hidden = group !== "all" && panel.dataset.group !== group
    })
  }
}
