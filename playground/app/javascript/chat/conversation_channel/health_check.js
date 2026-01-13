import logger from "../../logger"
import { jsonRequest } from "../../request_helpers"

export function startHealthCheck(controller) {
  if (!controller.healthUrlValue) return

  setTimeout(() => performHealthCheck(controller), 5000)

  controller.healthCheckIntervalId = setInterval(
    () => performHealthCheck(controller),
    controller.healthCheckIntervalValue
  )
}

export function stopHealthCheck(controller) {
  if (controller.healthCheckIntervalId) {
    clearInterval(controller.healthCheckIntervalId)
    controller.healthCheckIntervalId = null
  }
}

export async function performHealthCheck(controller) {
  if (!controller.healthUrlValue) return

  if (
    controller.cableConnected !== false
    && controller.hasTypingIndicatorTarget
    && !controller.typingIndicatorTarget.classList.contains("hidden")
  ) {
    return
  }

  if (controller.hasRunErrorAlertTarget && !controller.runErrorAlertTarget.classList.contains("hidden")) {
    return
  }

  try {
    const { response, data: health } = await jsonRequest(controller.healthUrlValue, {
      method: "GET"
    })

    if (!response.ok || !health) return
    handleHealthStatus(controller, health)
  } catch (error) {
    logger.debug("Health check failed:", error)
  }
}

export function handleHealthStatus(controller, health) {
  const { status, message, action: _action, details } = health

  const statusKey = `${status}:${details?.run_id || "none"}`
  if (controller.lastHealthStatus === statusKey) return
  controller.lastHealthStatus = statusKey

  switch (status) {
    case "healthy":
      controller.hideIdleAlert()
      break

    case "stuck":
      if (controller.hasTypingIndicatorTarget && controller.typingIndicatorTarget.classList.contains("hidden")) {
        controller.showTypingIndicator({
          name: details.speaker_name || "AI",
          space_membership_id: details.speaker_membership_id
        })
      }
      controller.showStuckWarning()
      break

    case "failed":
      controller.showRunErrorAlert({
        run_id: details.run_id,
        message: message
      })
      break

    case "idle_unexpected":
      controller.showIdleAlert(details)
      break
  }
}
