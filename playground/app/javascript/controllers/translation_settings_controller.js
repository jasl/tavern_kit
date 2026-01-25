import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mode", "translateBothOnly"]

  connect() {
    this.update()
  }

  modeChanged() {
    this.update()
  }

  update() {
    if (!this.hasModeTarget) return

    const isNative = this.modeTarget.value === "native"

    this.translateBothOnlyTargets.forEach((container) => {
      container.classList.toggle("hidden", isNative)
      container.setAttribute("aria-hidden", isNative ? "true" : "false")

      container.querySelectorAll("input, select, textarea, button").forEach((field) => {
        field.toggleAttribute("disabled", isNative)
      })
    })
  }
}

