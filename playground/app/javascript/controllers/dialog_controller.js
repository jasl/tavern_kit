import { Controller } from "@hotwired/stimulus"
import logger from "../logger"

/**
 * Dialog Controller
 *
 * Replaces inline `onclick="document.getElementById(...).showModal()"` usage.
 *
 * Usage:
 *   <button type="button"
 *           data-controller="dialog"
 *           data-dialog-id-value="import_modal"
 *           data-action="click->dialog#open">
 *     Open
 *   </button>
 *
 *   <button type="button"
 *           data-controller="dialog"
 *           data-dialog-id-value="import_modal"
 *           data-action="click->dialog#close">
 *     Close
 *   </button>
 */
export default class extends Controller {
  static values = {
    id: String
  }

  open(event) {
    event?.preventDefault()
    const dialog = this.findDialog()
    if (!dialog) return

    if (dialog.open) return

    try {
      dialog.showModal()
    } catch (error) {
      logger.warn("[dialog] Failed to open dialog:", error)
    }
  }

  close(event) {
    event?.preventDefault()
    const dialog = this.findDialog()
    if (!dialog) return

    if (!dialog.open) return

    try {
      dialog.close()
    } catch (error) {
      logger.warn("[dialog] Failed to close dialog:", error)
    }
  }

  toggle(event) {
    event?.preventDefault()
    const dialog = this.findDialog()
    if (!dialog) return

    if (dialog.open) {
      this.close(event)
    } else {
      this.open(event)
    }
  }

  findDialog() {
    const id = this.idValue
    if (id) {
      const dialog = document.getElementById(id)
      if (!dialog) {
        logger.warn(`[dialog] Dialog not found: #${id}`)
        return null
      }

      if (dialog instanceof HTMLDialogElement) return dialog

      logger.warn(`[dialog] Element is not a <dialog>: #${id}`)
      return null
    }

    const dialog = this.element.closest("dialog")
    if (dialog instanceof HTMLDialogElement) return dialog

    logger.warn("[dialog] Missing data-dialog-id-value and no ancestor <dialog> found")
    return null
  }
}
