import { Controller } from "@hotwired/stimulus"
import { connect, disconnect, toggle } from "../ui/runs_panel_auto_refresh/bindings"

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
    connect(this)
  }

  disconnect() {
    disconnect(this)
  }

  /**
   * Handle toggle change - start or stop auto refresh.
   */
  toggle() {
    toggle(this)
  }
}
