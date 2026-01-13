import logger from "../../logger"
import { AUTO_MODE_DISABLED_EVENT, dispatchWindowEvent } from "../events"
import { jsonPatch, showToast, withRequestLock } from "../../request_helpers"

export function handleUserTypingDisable(controller) {
  if (!controller.fullValue) return
  controller.disableCopilotDueToUserTyping()
}

export async function disableCopilotDueToUserTyping(controller) {
  controller.fullValue = false
  controller.updateUIForMode()

  if (controller.hasStepsCounterTarget && controller.hasFullToggleTarget) {
    const defaultSteps = controller.fullToggleTarget.dataset?.copilotDefaultSteps || "4"
    controller.stepsCounterTarget.textContent = defaultSteps
  }

  try {
    const { response } = await jsonPatch(controller.membershipUpdateUrlValue, {
      body: { space_membership: { copilot_mode: "none" } }
    })

    if (response.ok) {
      showToast("Copilot disabled - you are typing", "info", 5000)
    }
  } catch (error) {
    logger.warn("Failed to disable copilot:", error)
  }
}

export function handleCopilotDisabled(controller, data) {
  const error = data?.error
  const reason = data?.reason

  logger.warn("Copilot mode disabled:", { error, reason })

  controller.fullValue = false
  controller.updateUIForMode()

  if (controller.hasStepsCounterTarget && controller.hasFullToggleTarget) {
    const defaultSteps = controller.fullToggleTarget.dataset?.copilotDefaultSteps || "4"
    controller.stepsCounterTarget.textContent = defaultSteps
  }

  if (controller.hasTextareaTarget) {
    controller.textareaTarget.focus()
  }

  let message = "Copilot disabled."
  let type = "warning"

  if (reason === "remaining_steps_exhausted") {
    message = "Copilot disabled: remaining steps exhausted."
    type = "info"
  } else if (error) {
    message = `Copilot disabled: ${error}`
    type = "warning"
  } else if (reason) {
    message = `Copilot disabled (${reason}).`
    type = "warning"
  }

  showToast(message, type, 5000)
}

export function handleCopilotStepsUpdated(controller, data) {
  const remainingSteps = data?.remaining_steps
  if (remainingSteps === undefined || remainingSteps === null) return

  if (controller.hasStepsCounterTarget) {
    controller.stepsCounterTarget.textContent = remainingSteps
  }
}

export async function toggleFullMode(controller, event) {
  await withRequestLock(controller.membershipUpdateUrlValue, async () => {
    const wasEnabled = controller.fullValue
    const newMode = wasEnabled ? "none" : "full"

    controller.fullValue = !wasEnabled
    controller.updateUIForMode()

    const toggleBtn = event?.currentTarget || controller.fullToggleTarget

    if (controller.hasStepsCounterTarget) {
      const defaultSteps = toggleBtn?.dataset?.copilotDefaultSteps || "4"
      controller.stepsCounterTarget.textContent = defaultSteps
    }

    try {
      const { response, data } = await jsonPatch(controller.membershipUpdateUrlValue, {
        body: { space_membership: { copilot_mode: newMode } }
      })

      if (!response.ok) {
        controller.fullValue = wasEnabled
        controller.updateUIForMode()
        showToast("Failed to update Copilot mode", "error", 5000)
        return
      }

      const payload = data || {}
      if (payload.copilot_remaining_steps !== undefined && controller.hasStepsCounterTarget) {
        controller.stepsCounterTarget.textContent = payload.copilot_remaining_steps
      }

      if (payload.auto_mode_disabled) {
        notifyAutoModeDisabled(payload.auto_mode_remaining_rounds || 0)
        showToast("Copilot enabled, Auto mode disabled", "success", 5000)
        return
      }

      showToast(newMode === "full" ? "Copilot enabled" : "Copilot disabled", "success", 5000)
    } catch (error) {
      logger.error("Copilot mode update failed:", error)
      controller.fullValue = wasEnabled
      controller.updateUIForMode()
      showToast("Failed to update Copilot mode", "error", 5000)
    }
  })
}

export function updateUIForMode(controller) {
  const enabled = controller.fullValue

  if (controller.hasTextareaTarget) {
    controller.textareaTarget.placeholder = enabled
      ? "Copilot is active. Type here to take over..."
      : "Type your message..."
  }

  if (controller.hasGenerateBtnTarget) {
    controller.generateBtnTarget.disabled = enabled
  }
  if (controller.hasCountBtnTarget) {
    controller.countBtnTarget.disabled = enabled
  }

  if (controller.hasFullToggleTarget) {
    const btn = controller.fullToggleTarget
    if (enabled) {
      btn.classList.remove("btn-ghost")
      btn.classList.add("btn-success")
    } else {
      btn.classList.remove("btn-success")
      btn.classList.add("btn-ghost")
    }
  }
}

export function notifyAutoModeDisabled(remainingRounds) {
  dispatchWindowEvent(AUTO_MODE_DISABLED_EVENT, { remainingRounds }, { cancelable: true })
}

