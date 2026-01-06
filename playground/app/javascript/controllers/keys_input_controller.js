import { Controller } from "@hotwired/stimulus"

/**
 * Keys Input Controller
 *
 * Provides a chip-based input for lorebook keys with support for:
 * - Comma-separated key entry
 * - Regex pattern detection (/pattern/flags)
 * - Visual distinction between regular keys and regex patterns
 */
export default class extends Controller {
  static targets = ["hidden", "container", "input"]
  static values = { value: Array }

  connect() {
    this.keys = this.valueValue || []
    this.render()
  }

  handleKeydown(event) {
    const input = event.target
    const value = input.value.trim()

    if (event.key === "Enter" || event.key === ",") {
      event.preventDefault()
      if (value) {
        this.addKey(value)
        input.value = ""
      }
    } else if (event.key === "Backspace" && !value && this.keys.length > 0) {
      this.removeLastKey()
    }
  }

  addKey(key) {
    key = key.replace(/,$/, "").trim()
    if (key && !this.keys.includes(key)) {
      this.keys.push(key)
      this.updateHidden()
      this.render()
    }
  }

  remove(event) {
    const key = event.currentTarget.dataset.key
    this.keys = this.keys.filter(k => k !== key)
    this.updateHidden()
    this.render()
  }

  removeLastKey() {
    this.keys.pop()
    this.updateHidden()
    this.render()
  }

  updateHidden() {
    if (this.hasHiddenTarget) {
      this.hiddenTarget.value = JSON.stringify(this.keys)
    }
  }

  render() {
    if (!this.hasContainerTarget || !this.hasInputTarget) return

    // Clear existing badges
    const badges = this.containerTarget.querySelectorAll(".badge")
    badges.forEach(badge => badge.remove())

    // Add badges for each key
    this.keys.forEach(key => {
      const isRegex = this.isRegexKey(key)
      const badge = document.createElement("span")
      badge.className = `badge badge-sm gap-1 ${isRegex ? "badge-secondary" : "badge-primary"}`

      // Create text node for key display (safe from XSS)
      const keyText = document.createTextNode(key)
      badge.appendChild(keyText)

      // Create remove button with proper attribute escaping
      const button = document.createElement("button")
      button.type = "button"
      button.className = "hover:text-error"
      button.dataset.action = "keys-input#remove"
      button.dataset.key = key  // Safe: dataset assignment escapes automatically
      button.textContent = "×"
      badge.appendChild(button)

      this.containerTarget.insertBefore(badge, this.inputTarget)
    })
  }

  isRegexKey(key) {
    return /^\/.*\/[gimsuy]*$/.test(key)
  }
}
