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
let turboStreamGuardInstalled = false

export default class extends Controller {
  static values = {
    spaceId: Number,
    renderSeq: Number
  }

  connect() {
    // Queue is rendered server-side and updated via Turbo Streams
    // This controller is available for future client-side enhancements
    this.#installTurboStreamGuard()
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

  #installTurboStreamGuard() {
    if (turboStreamGuardInstalled) return
    turboStreamGuardInstalled = true

    document.addEventListener("turbo:before-stream-render", (event) => {
      const stream = event.target
      if (!stream || stream.tagName !== "TURBO-STREAM") return
      if (stream.getAttribute("action") !== "replace") return

      const targetId = stream.getAttribute("target")
      if (!targetId) return

      const current = document.getElementById(targetId)
      if (!current) return

      const currentSeqRaw = current.getAttribute("data-group-queue-render-seq-value")
      if (!currentSeqRaw) return // not a group queue element

      const template = stream.querySelector("template")
      const incoming = template?.content?.firstElementChild
      const incomingSeqRaw = incoming?.getAttribute("data-group-queue-render-seq-value")

      const currentSeq = Number(currentSeqRaw)
      const incomingSeq = Number(incomingSeqRaw)

      if (Number.isFinite(currentSeq) && Number.isFinite(incomingSeq) && incomingSeq <= currentSeq) {
        event.preventDefault()
      }
    })
  }
}
