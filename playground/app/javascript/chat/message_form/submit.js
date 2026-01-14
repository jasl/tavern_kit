import { showToast } from "../../request_helpers"

export function handleKeydown(controller, event) {
  // Submit on Enter (without Shift, Ctrl, Alt, or Meta)
  if (event.key === "Enter" && !event.shiftKey && !event.ctrlKey && !event.altKey && !event.metaKey) {
    if (controller.cableConnectedValue === false) {
      event.preventDefault()
      showToast("Disconnected. Reconnecting…", "warning")
      return
    }

    event.preventDefault()

    const form = controller.element.closest("form") || controller.element.querySelector("form")
    if (form) {
      // Use requestSubmit to trigger validation and submit events
      form.requestSubmit()
    }
  }
}

export function handleSubmitEnd(controller, event) {
  const textarea = controller.hasTextareaTarget
    ? controller.textareaTarget
    : controller.element.querySelector("textarea")

  if (!event.detail?.success) {
    const fetchResponse = event.detail?.fetchResponse
    const toastAlreadyShown = fetchResponse?.header?.("X-TavernKit-Toast") === "1"
    if (toastAlreadyShown) return

    // Use Turbo's statusCode getter for reliable status retrieval
    const status = fetchResponse?.statusCode

    if (status === 423) {
      showToast("AI is generating a response. Please wait…", "warning")
    } else if (status === 409) {
      showToast("Message not sent due to a conflict. Please try again.", "warning")
    } else {
      showToast("Message not sent. Please try again.", "error")
    }

    return
  }

  if (event.detail?.fetchResponse && textarea) {
    textarea.value = ""
  }
}
