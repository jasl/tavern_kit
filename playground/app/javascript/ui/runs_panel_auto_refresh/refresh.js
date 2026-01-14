import logger from "../../logger"
import { refreshTurboFrame } from "../turbo_frame/refresh"

export async function refreshPanel(controller) {
  const frameId = controller.frameIdValue
  if (!frameId) return

  const url = new URL(window.location.href)

  try {
    await refreshTurboFrame(frameId, url.toString())
  } catch (error) {
    logger.error("[RunsPanelAutoRefresh] Failed to refresh:", error)
  }
}
