import { Controller } from "@hotwired/stimulus"

/**
 * Group Queue Controller
 *
 * Manages the group chat queue display shown above the message input.
 * The queue shows predicted speakers with their avatars.
 *
 * Features:
 * - Avatar tooltips are handled by daisyUI tooltip classes
 * - Settings toggles auto-submit via auto-submit controller
 * - Queue updates come via Turbo Streams (server-rendered)
 *
 * This controller handles any additional client-side interactions needed.
 */
export default class extends Controller {
  static values = {
    spaceId: Number
  }

  connect() {
    // Queue is rendered server-side and updated via Turbo Streams
    // This controller is available for future client-side enhancements
  }

  disconnect() {
    // Cleanup if needed
  }

  /**
   * Refresh the queue display.
   * Can be called programmatically if needed.
   */
  refresh() {
    // The queue is updated via Turbo Streams from the server
    // This method is a placeholder for any manual refresh logic
  }
}
