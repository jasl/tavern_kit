import logger from "../../logger"
import { AUTO_WITHOUT_HUMAN_DISABLED_EVENT, dispatchWindowEvent } from "../events"
import { jsonPatch, showToast, withRequestLock } from "../../request_helpers"

export function handleUserTypingDisable(controller) {
  if (!controller.autoValue) return
  controller.disableAutoDueToUserTyping()
}

export async function disableAutoDueToUserTyping(controller) {
  controller.autoValue = false
  controller.updateUIForMode()

  if (controller.hasStepsCounterTarget && controller.hasAutoToggleTarget) {
    const defaultSteps = controller.autoToggleTarget.dataset?.autoDefaultSteps || "1"
    controller.stepsCounterTarget.textContent = defaultSteps
  }

  try {
    const { response } = await jsonPatch(controller.membershipUpdateUrlValue, {
      body: { space_membership: { auto: "none" } }
    })

    if (response.ok) {
      showToast("Auto disabled - you are typing", "info", 5000)
    }
  } catch (error) {
    logger.warn("Failed to disable auto:", error)
  }
}

export function handleAutoDisabled(controller, data) {
  const error = data?.error
  const reason = data?.reason

  logger.warn("Auto disabled:", { error, reason })

  controller.autoValue = false
  controller.updateUIForMode()

  if (controller.hasStepsCounterTarget && controller.hasAutoToggleTarget) {
    const defaultSteps = controller.autoToggleTarget.dataset?.autoDefaultSteps || "1"
    controller.stepsCounterTarget.textContent = defaultSteps
  }

  if (controller.hasTextareaTarget) {
    controller.textareaTarget.focus()
  }

  let message = "Auto disabled."
  let type = "warning"

  if (reason === "remaining_steps_exhausted") {
    message = "Auto disabled: remaining steps exhausted."
    type = "info"
  } else if (error) {
    message = `Auto disabled: ${error}`
    type = "warning"
  } else if (reason) {
    message = `Auto disabled (${reason}).`
    type = "warning"
  }

  showToast(message, type, 5000)
}

export function handleAutoStepsUpdated(controller, data) {
  const remainingSteps = data?.remaining_steps
  if (remainingSteps === undefined || remainingSteps === null) return

  if (controller.hasStepsCounterTarget) {
    controller.stepsCounterTarget.textContent = remainingSteps
  }
}

export async function toggleAutoMode(controller, event) {
  await withRequestLock(controller.membershipUpdateUrlValue, async () => {
    const wasEnabled = controller.autoValue
    const newMode = wasEnabled ? "none" : "auto"

    controller.autoValue = !wasEnabled
    controller.updateUIForMode()

    const toggleBtn = event?.currentTarget || controller.autoToggleTarget

    if (controller.hasStepsCounterTarget) {
      const defaultSteps = toggleBtn?.dataset?.autoDefaultSteps || "1"
      controller.stepsCounterTarget.textContent = defaultSteps
    }

    try {
      const { response, data } = await jsonPatch(controller.membershipUpdateUrlValue, {
        body: { space_membership: { auto: newMode } }
      })

      if (!response.ok) {
        controller.autoValue = wasEnabled
        controller.updateUIForMode()
        showToast("Failed to update Auto", "error", 5000)
        return
      }

      const payload = data || {}
      if (payload.auto_remaining_steps !== undefined && payload.auto_remaining_steps !== null && controller.hasStepsCounterTarget) {
        controller.stepsCounterTarget.textContent = payload.auto_remaining_steps
      }

      if (payload.auto_without_human_disabled) {
        notifyAutoWithoutHumanDisabled(payload.auto_without_human_remaining_rounds || 0)
        showToast("Auto enabled, Auto without human disabled", "success", 5000)
        return
      }

      showToast(newMode === "auto" ? "Auto enabled" : "Auto disabled", "success", 5000)
    } catch (error) {
      logger.error("Auto update failed:", error)
      controller.autoValue = wasEnabled
      controller.updateUIForMode()
      showToast("Failed to update Auto", "error", 5000)
    }
  })
}

export function updateUIForMode(controller) {
  const enabled = controller.autoValue

  if (controller.hasTextareaTarget) {
    controller.textareaTarget.placeholder = enabled
      ? "Auto is active. Type here to take over..."
      : "Type your message..."
  }

  if (controller.hasGenerateBtnTarget) {
    controller.generateBtnTarget.disabled = enabled
  }
  if (controller.hasCountBtnTarget) {
    controller.countBtnTarget.disabled = enabled
  }

  if (controller.hasAutoToggleTarget) {
    const btn = controller.autoToggleTarget
    if (enabled) {
      btn.classList.remove("btn-ghost")
      btn.classList.add("btn-success")
    } else {
      btn.classList.remove("btn-success")
      btn.classList.add("btn-ghost")
    }
  }
}

export function notifyAutoWithoutHumanDisabled(remainingRounds) {
  dispatchWindowEvent(AUTO_WITHOUT_HUMAN_DISABLED_EVENT, { remainingRounds }, { cancelable: true })
}
