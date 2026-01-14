import { disableUntilReplaced, showToast, withRequestLock } from "../../request_helpers"
import { toggleAutoMode } from "./requests"
import { updateButtonUI } from "./ui"

export function handleAutoModeDisabled(controller, event) {
  const _remainingRounds = event?.detail?.remainingRounds || 0
  controller.enabledValue = false
  updateButtonUI(controller, false, controller.defaultRoundsValue)
}

export function handleUserTypingDisable(controller) {
  if (!controller.enabledValue) return
  disableAutoModeDueToUserTyping(controller)
}

export async function disableAutoModeDueToUserTyping(controller) {
  await withRequestLock(controller.urlValue, async () => {
    controller.enabledValue = false
    updateButtonUI(controller, false, controller.defaultRoundsValue)

    const success = await toggleAutoMode(controller, 0)
    if (success) {
      showToast("Auto mode disabled - you are typing", "info")
      return
    }

    controller.enabledValue = true
    updateButtonUI(controller, true, controller.defaultRoundsValue)
  })
}

async function applyAutoMode(controller, rounds, { button = null, enabledRounds = null } = {}) {
  const roundsWhenEnabled = enabledRounds ?? rounds
  const roundsWhenDisabled = controller.defaultRoundsValue

  await withRequestLock(controller.urlValue, async () => {
    const run = async () => {
      const enabling = rounds > 0

      controller.enabledValue = enabling
      updateButtonUI(controller, enabling, enabling ? roundsWhenEnabled : roundsWhenDisabled)

      const success = await toggleAutoMode(controller, rounds)
      if (!success) {
        controller.enabledValue = !enabling
        updateButtonUI(controller, !enabling, roundsWhenDisabled)
      }

      return success
    }

    if (button) {
      await disableUntilReplaced(button, run)
      return
    }

    await run()
  })
}

export async function start(controller, event) {
  event.preventDefault()

  const button = event.currentTarget || (controller.hasButtonTarget ? controller.buttonTarget : null)

  await applyAutoMode(controller, controller.defaultRoundsValue, { button })
}

export async function startOne(controller, event) {
  event.preventDefault()

  const button = event.currentTarget || (controller.hasButton1Target ? controller.button1Target : null)

  await applyAutoMode(controller, 1, { button, enabledRounds: 1 })
}

export async function stop(controller, event) {
  event.preventDefault()

  const button = event.currentTarget || (controller.hasButtonTarget ? controller.buttonTarget : null)

  await applyAutoMode(controller, 0, { button })
}
