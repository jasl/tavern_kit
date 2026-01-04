import { Controller } from "@hotwired/stimulus"

/**
 * Theme Controller
 *
 * Handles light/dark theme toggle.
 * Uses data-theme attribute on <html> element.
 */
export default class extends Controller {
  static targets = ["checkbox"]

  connect() {
    // Initialize checkbox state based on current theme
    const currentTheme = document.documentElement.getAttribute("data-theme") || "light"
    if (this.hasCheckboxTarget) {
      this.checkboxTarget.checked = currentTheme === "dark"
    }
  }

  toggle() {
    const isDark = this.hasCheckboxTarget ? this.checkboxTarget.checked : false
    const newTheme = isDark ? "dark" : "light"
    document.documentElement.setAttribute("data-theme", newTheme)

    // Persist preference
    localStorage.setItem("theme", newTheme)
  }
}
