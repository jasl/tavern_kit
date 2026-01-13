import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { turboRequest } from "../request_helpers"

/**
 * Pending Characters Controller
 *
 * Polls for pending character updates to handle race conditions where
 * Turbo Stream broadcasts might be missed during page load/refresh.
 *
 * This controller periodically checks if any pending characters have been
 * processed and refreshes them via a Turbo Stream request.
 */
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 2000 }
  }

  connect() {
    // Use MutationObserver to detect when new pending cards are added
    this.observer = new MutationObserver(() => this.checkForPendingCharacters())
    this.observer.observe(this.element, { childList: true, subtree: true })

    // Initial check
    this.checkForPendingCharacters()
  }

  disconnect() {
    this.stopPolling()
    if (this.observer) {
      this.observer.disconnect()
      this.observer = null
    }
  }

  checkForPendingCharacters() {
    const pendingCards = this.element.querySelectorAll('[data-status="pending"]')
    if (pendingCards.length > 0) {
      this.startPolling()
    } else {
      this.stopPolling()
    }
  }

  startPolling() {
    if (this.pollTimer) return

    // Do an immediate first poll
    this.refreshPendingCharacters()

    // Then continue polling at interval
    this.pollTimer = setInterval(() => {
      this.refreshPendingCharacters()
    }, this.intervalValue)
  }

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer)
      this.pollTimer = null
    }
  }

  async refreshPendingCharacters() {
    const pendingCards = this.element.querySelectorAll('[data-status="pending"]')

    if (pendingCards.length === 0) {
      this.stopPolling()
      return
    }

    // Get IDs of pending characters
    const pendingIds = Array.from(pendingCards).map(card => {
      // Extract ID from dom_id format: "character_123" -> "123"
      const match = card.id.match(/character_(\d+)/)
      return match ? match[1] : null
    }).filter(Boolean)

    if (pendingIds.length === 0) {
      this.stopPolling()
      return
    }

    try {
      // Fetch updated status for pending characters
      const { response, renderedTurboStream, turboStreamHtml } = await turboRequest(`${this.urlValue}?ids=${pendingIds.join(",")}`, {
        accept: "text/vnd.turbo-stream.html"
      })

      if (!response.ok || response.status === 204) return
      if (!renderedTurboStream || !turboStreamHtml?.trim()) return

      // Recheck after update
      this.checkForPendingCharacters()
    } catch (error) {
      logger.error("Failed to refresh pending characters:", error)
    }
  }
}
