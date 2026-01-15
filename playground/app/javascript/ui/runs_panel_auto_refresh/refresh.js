import logger from "../../logger"
import { refreshTurboFrame } from "../turbo_frame/refresh"

export async function refreshPanel(controller) {
  const frameId = controller.frameIdValue
  if (!frameId) return

  // Use the dedicated runs endpoint URL if provided, otherwise fall back to current URL
  const url = controller.urlValue || window.location.href

  try {
    await refreshTurboFrame(frameId, url)
  } catch (error) {
    logger.error("[RunsPanelAutoRefresh] Failed to refresh:", error)
  }
}
