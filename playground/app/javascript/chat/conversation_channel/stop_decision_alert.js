import logger from "../../logger"
import { showToastIfNeeded, turboRequest, withRequestLock } from "../../request_helpers"

export function showStopDecisionAlert(controller, details) {
  const speakerName = details?.paused_speaker_name || details?.speaker_name

  if (controller.hasStopDecisionMessageTarget && speakerName) {
    controller.stopDecisionMessageTarget.textContent = `Stopped. ${speakerName} was interrupted.`
  }

  if (controller.hasStopDecisionAlertTarget) {
    controller.stopDecisionAlertTarget.classList.remove("hidden")
  }
}

export function hideStopDecisionAlert(controller) {
  if (controller.hasStopDecisionAlertTarget) {
    controller.stopDecisionAlertTarget.classList.add("hidden")
  }
}

export async function retryFromStopDecision(controller, event) {
  event?.preventDefault?.()

  const url = controller.retryCurrentSpeakerUrlValue
  if (!url) {
    logger.warn("No retryCurrentSpeaker URL configured")
    return
  }

  hideStopDecisionAlert(controller)

  const { skipped, value } = await withRequestLock(url, async () => {
    return await turboRequest(url, { method: "POST" })
  })
  if (skipped) return

  const { response, toastAlreadyShown } = value || {}
  if (!response?.ok) {
    showToastIfNeeded(toastAlreadyShown, "Failed to retry. Please try again.", "error")
    showStopDecisionAlert(controller, {})
  }
}

export async function skipFromStopDecision(controller, event) {
  event?.preventDefault?.()

  const url = controller.skipCurrentSpeakerUrlValue
  if (!url) {
    logger.warn("No skipCurrentSpeaker URL configured")
    return
  }

  hideStopDecisionAlert(controller)

  const { skipped, value } = await withRequestLock(url, async () => {
    return await turboRequest(url, { method: "POST" })
  })
  if (skipped) return

  const { response, toastAlreadyShown } = value || {}
  if (!response?.ok) {
    showToastIfNeeded(toastAlreadyShown, "Failed to skip. Please try again.", "error")
    showStopDecisionAlert(controller, {})
  }
}
