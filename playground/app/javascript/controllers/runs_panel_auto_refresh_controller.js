import { Controller } from "@hotwired/stimulus"

/**
 * Runs Panel Auto Refresh Controller
 *
 * Controls automatic refreshing of the Recent Runs panel.
 * Default: OFF (for easier debugging)
 * When enabled: Polls the server periodically to refresh the runs list.
 *
 * The preference is stored in localStorage.
 */
export default class extends Controller {
  static targets = ["toggle", "container"]
  static values = {
    conversationId: Number,
    interval: { type: Number, default: 5000 }, // 5 seconds default
    frameId: String
  }

  connect() {
    this.refreshTimer = null

    // Restore preference from localStorage
    const stored = localStorage.getItem("runsPanel.autoRefresh")
    const shouldEnable = stored === "true"

    if (this.hasToggleTarget) {
      this.toggleTarget.checked = shouldEnable
    }

    if (shouldEnable) {
      this.startAutoRefresh()
    }
  }

  disconnect() {
    this.stopAutoRefresh()
  }

  /**
   * Handle toggle change - start or stop auto refresh.
   */
  toggle() {
    const enabled = this.toggleTarget.checked

    // Save preference
    localStorage.setItem("runsPanel.autoRefresh", enabled ? "true" : "false")

    if (enabled) {
      this.startAutoRefresh()
      this.showToast("Auto-refresh enabled", "info")
    } else {
      this.stopAutoRefresh()
      this.showToast("Auto-refresh disabled", "info")
    }
  }

  /**
   * Start the auto-refresh timer.
   */
  startAutoRefresh() {
    this.stopAutoRefresh() // Clear any existing timer

    this.refreshTimer = setInterval(() => {
      this.refreshPanel()
    }, this.intervalValue)
  }

  /**
   * Stop the auto-refresh timer.
   */
  stopAutoRefresh() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
      this.refreshTimer = null
    }
  }

  /**
   * Refresh the runs panel by requesting a Turbo Frame update.
   */
  async refreshPanel() {
    const frameId = this.frameIdValue
    if (!frameId) return

    const frame = document.getElementById(frameId)
    if (!frame) return

    // Get the current URL with the target_membership_id param if present
    const url = new URL(window.location.href)

    try {
      // Use Turbo to reload the frame
      const response = await fetch(url.toString(), {
        headers: {
          "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
          "Turbo-Frame": frameId
        }
      })

      if (response.ok) {
        const html = await response.text()

        // Parse and extract the frame content
        const parser = new DOMParser()
        const doc = parser.parseFromString(html, "text/html")
        const newFrame = doc.getElementById(frameId)

        if (newFrame && frame) {
          frame.innerHTML = newFrame.innerHTML
        }
      }
    } catch (error) {
      console.error("[RunsPanelAutoRefresh] Failed to refresh:", error)
    }
  }

  /**
   * Show a toast notification.
   *
   * @param {string} message - The message to show
   * @param {string} type - The type of toast (info, success, error, warning)
   */
  showToast(message, type = "info") {
    const event = new CustomEvent("toast:show", {
      bubbles: true,
      detail: { message, type, duration: 2000 }
    })
    this.element.dispatchEvent(event)
  }
}
