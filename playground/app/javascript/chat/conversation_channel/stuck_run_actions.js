import logger from "../../logger"
import { showToast, showToastIfNeeded, turboPost } from "../../request_helpers"

export function confirmCancelStuckRun(controller, event) {
  event.preventDefault()

  const confirmed = confirm(
    "Cancel this AI response?\n\n" +
    "This will stop the current generation and may affect the conversation flow. " +
    "You can use 'Retry' to try again instead."
  )

  if (confirmed) {
    cancelStuckRun(controller, event)
  }
}

export async function cancelStuckRun(controller, event) {
  event.preventDefault()

  const url = controller.cancelUrlValue
  if (!url) {
    logger.warn("No cancel URL configured")
    return
  }

  try {
    const { response, toastAlreadyShown } = await turboPost(url)

    if (response.ok) {
      controller.hideTypingIndicator()
      controller.hideStuckWarning()
    } else {
      showToastIfNeeded(toastAlreadyShown, "Failed to cancel run. Please try again.", "error")
    }
  } catch (error) {
    logger.error("Error canceling stuck run:", error)
    showToast("Failed to cancel run. Please try again.", "error")
  }
}

export async function retryStuckRun(controller, event) {
  event.preventDefault()

  const url = controller.retryUrlValue
  if (!url) {
    logger.warn("No retry URL configured")
    return
  }

  controller.hideStuckWarning()
  controller.lastChunkAt = Date.now()

  try {
    const { response, toastAlreadyShown } = await turboPost(url)

    if (!response.ok) {
      showToastIfNeeded(toastAlreadyShown, "Failed to retry run. Please try again.", "error")
      controller.showStuckWarning()
    }
  } catch (error) {
    logger.error("Error retrying stuck run:", error)
    showToast("Failed to retry run. Please try again.", "error")
    controller.showStuckWarning()
  }
}
