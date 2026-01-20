import logger from "../../logger"
import { showToast, showToastIfNeeded, turboPost } from "../../request_helpers"

export async function toggleAutoWithoutHuman(controller, rounds) {
  if (!controller.hasUrlValue) {
    logger.error("Auto-without-human toggle URL not configured")
    return false
  }

  try {
    const { response, toastAlreadyShown } = await turboPost(controller.urlValue, {
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `rounds=${rounds}`
    })

    if (!response.ok) {
      logger.error("Failed to toggle auto-without-human:", response.status)
      showToastIfNeeded(
        toastAlreadyShown,
        rounds > 0 ? "Failed to start auto-without-human" : "Failed to stop auto-without-human",
        "error"
      )
      return false
    }

    return true
  } catch (error) {
    logger.error("Failed to toggle auto-without-human:", error)
    showToast("Failed to toggle auto-without-human", "error")
    return false
  }
}
