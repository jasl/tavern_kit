import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mode", "translateBothOnly", "nativeOnly", "nativePromptComponentsEnabled"]

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
      const allowInNative =
        this.hasNativePromptComponentsEnabledTarget && this.nativePromptComponentsEnabledTarget.checked === true

      const shouldHide = isNative && !allowInNative

      container.classList.toggle("hidden", shouldHide)
      container.setAttribute("aria-hidden", shouldHide ? "true" : "false")

      container.querySelectorAll("input, select, textarea, button").forEach((field) => {
        field.toggleAttribute("disabled", shouldHide)
      })
    })

    this.nativeOnlyTargets.forEach((container) => {
      const shouldHide = !isNative

      container.classList.toggle("hidden", shouldHide)
      container.setAttribute("aria-hidden", shouldHide ? "true" : "false")

      container.querySelectorAll("input, select, textarea, button").forEach((field) => {
        field.toggleAttribute("disabled", shouldHide)
      })
    })
  }
}
