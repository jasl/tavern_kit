import logger from "../../logger"
import { showToast, showToastIfNeeded, turboRequest } from "../../request_helpers"

export function showIdleAlert(controller, details) {
  if (controller.hasIdleAlertMessageTarget) {
    controller.idleAlertMessageTarget.textContent = "Conversation seems stuck. No AI is responding."
  }

  if (controller.hasIdleAlertSpeakerTarget && details?.suggested_speaker_name) {
    controller.idleAlertSpeakerTarget.textContent = details.suggested_speaker_name
    controller.idleAlertSpeakerTarget.dataset.speakerId = details.suggested_speaker_id || ""
  }

  if (controller.hasIdleAlertTarget) {
    controller.idleAlertTarget.classList.remove("hidden")
  }
}

export function hideIdleAlert(controller) {
  if (controller.hasIdleAlertTarget) {
    controller.idleAlertTarget.classList.add("hidden")
  }

  if (controller.lastHealthStatus?.startsWith("idle_unexpected")) {
    controller.lastHealthStatus = null
  }
}

export async function generateFromIdleAlert(controller, event) {
  event.preventDefault()

  const url = controller.generateUrlValue
  if (!url) {
    logger.warn("No generate URL configured")
    return
  }

  const speakerId = controller.hasIdleAlertSpeakerTarget
    ? controller.idleAlertSpeakerTarget.dataset.speakerId
    : null

  hideIdleAlert(controller)

  try {
    const formData = new FormData()
    if (speakerId) {
      formData.append("speaker_id", speakerId)
    }

    const { response, toastAlreadyShown } = await turboRequest(url, {
      method: "POST",
      body: formData
    })

    if (!response.ok) {
      showToastIfNeeded(toastAlreadyShown, "Failed to generate response. Please try again.", "error")
      showIdleAlert(controller, {})
    }
  } catch (error) {
    logger.error("Error generating response:", error)
    showToast("Failed to generate response. Please try again.", "error")
    showIdleAlert(controller, {})
  }
}
