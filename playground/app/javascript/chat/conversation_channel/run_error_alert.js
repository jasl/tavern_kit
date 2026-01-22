import logger from "../../logger"
import { showToast, showToastIfNeeded, turboPost } from "../../request_helpers"

export function showRunErrorAlert(controller, data) {
  const { run_id: runId, message } = data

  controller.failedRunId = runId

  controller.hideTypingIndicator()
  controller.hideStuckWarning()

  if (controller.hasRunErrorMessageTarget) {
    const text = message || "AI response failed. Click Retry to try again. Sending a new message will reset the round (Auto without human/Auto will be turned off)."
    controller.runErrorMessageTarget.textContent = text
    controller.runErrorMessageTarget.title = text
  }

  if (controller.hasRunErrorAlertTarget) {
    controller.runErrorAlertTarget.classList.remove("hidden")
  }
}

export function hideRunErrorAlert(controller) {
  if (controller.hasRunErrorAlertTarget) {
    controller.runErrorAlertTarget.classList.add("hidden")
  }
  controller.failedRunId = null
}

export async function retryFailedRun(controller, event) {
  event.preventDefault()

  const url = controller.retryUrlValue
  if (!url) {
    logger.warn("No retry URL configured")
    return
  }

  hideRunErrorAlert(controller)

  try {
    const { response, toastAlreadyShown } = await turboPost(url)

    if (!response.ok) {
      showToastIfNeeded(toastAlreadyShown, "Failed to retry. Please try again.", "error")
      if (controller.hasRunErrorAlertTarget) {
        controller.runErrorAlertTarget.classList.remove("hidden")
      }
    }
  } catch (error) {
    logger.error("Error retrying failed run:", error)
    showToast("Failed to retry. Please try again.", "error")
    if (controller.hasRunErrorAlertTarget) {
      controller.runErrorAlertTarget.classList.remove("hidden")
    }
  }
}
