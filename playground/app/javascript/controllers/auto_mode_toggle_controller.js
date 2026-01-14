import { Controller } from "@hotwired/stimulus"
import { bindAutoModeEvents } from "../chat/auto_mode/bindings"
import { start, startOne, stop } from "../chat/auto_mode/actions"

/**
 * Auto Mode Toggle Controller
 *
 * Handles starting/stopping auto-mode for AI-to-AI conversation in group chats.
 * Auto-mode allows AI characters to take turns automatically without requiring
 * user intervention.
 *
 * Features:
 * - Start auto-mode with a configurable number of rounds (default: 4)
 * - Stop auto-mode immediately
 * - Real-time UI updates via Turbo Streams
 * - Toast notifications for user feedback
 *
 * @example HTML structure
 *   <div data-controller="auto-mode-toggle"
 *        data-auto-mode-toggle-url-value="/conversations/123/toggle_auto_mode"
 *        data-auto-mode-toggle-default-rounds-value="4">
 *     <button data-action="click->auto-mode-toggle#start">Start</button>
 *     <button data-action="click->auto-mode-toggle#stop">Stop</button>
 *   </div>
 */
export default class extends Controller {
  static targets = ["button", "button1", "icon", "count"]

  static values = {
    url: String,
    defaultRounds: { type: Number, default: 4 },
    enabled: { type: Boolean, default: false }
  }

  connect() {
    this.disconnectEvents = bindAutoModeEvents(this)
  }

  disconnect() {
    this.disconnectEvents?.()
  }

  /**
   * Start auto-mode with the default number of rounds.
   */
  async start(event) {
    await start(this, event)
  }

  /**
   * Start auto-mode with just 1 round (skip current turn once).
   */
  async startOne(event) {
    await startOne(this, event)
  }

  /**
   * Stop auto-mode immediately.
   */
  async stop(event) {
    await stop(this, event)
  }
}
