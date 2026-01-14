import logger from "../../logger"
import { showToast, showToastIfNeeded, turboPost } from "../../request_helpers"

export async function toggleAutoMode(controller, rounds) {
  if (!controller.hasUrlValue) {
    logger.error("Auto-mode toggle URL not configured")
    return false
  }

  try {
    const { response, toastAlreadyShown } = await turboPost(controller.urlValue, {
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `rounds=${rounds}`
    })

    if (!response.ok) {
      logger.error("Failed to toggle auto-mode:", response.status)
      showToastIfNeeded(toastAlreadyShown, rounds > 0 ? "Failed to start auto-mode" : "Failed to stop auto-mode", "error")
      return false
    }

    return true
  } catch (error) {
    logger.error("Failed to toggle auto-mode:", error)
    showToast("Failed to toggle auto-mode", "error")
    return false
  }
}
