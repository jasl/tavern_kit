import { Controller } from "@hotwired/stimulus"
import { bindAutoWithoutHumanEvents } from "../chat/auto_without_human/bindings"
import { start, stop } from "../chat/auto_without_human/actions"

/**
 * Auto Without Human Toggle Controller
 *
 * Handles starting/stopping auto-without-human for AI-to-AI conversation in group chats.
 *
 * Chat UI is intentionally single-step: enabling always requests 1 round.
 * Backend still supports N rounds (1..10).
 */
export default class extends Controller {
  static targets = ["button", "icon", "count"]

  static values = {
    url: String,
    defaultRounds: { type: Number, default: 1 },
    enabled: { type: Boolean, default: false }
  }

  connect() {
    this.disconnectEvents = bindAutoWithoutHumanEvents(this)
  }

  disconnect() {
    this.disconnectEvents?.()
  }

  async toggle(event) {
    if (this.enabledValue) {
      await stop(this, event)
      return
    }

    await start(this, event)
  }
}
