import { disableUntilReplaced, showToast, withRequestLock } from "../../request_helpers"
import { toggleAutoWithoutHuman } from "./requests"
import { updateButtonUI } from "./ui"

export function handleAutoWithoutHumanDisabled(controller, event) {
  const _remainingRounds = event?.detail?.remainingRounds || 0
  controller.enabledValue = false
  updateButtonUI(controller, false, controller.defaultRoundsValue)
}

export function handleUserTypingDisable(controller) {
  if (!controller.enabledValue) return
  disableAutoWithoutHumanDueToUserTyping(controller)
}

export async function disableAutoWithoutHumanDueToUserTyping(controller) {
  await withRequestLock(controller.urlValue, async () => {
    controller.enabledValue = false
    updateButtonUI(controller, false, controller.defaultRoundsValue)

    const success = await toggleAutoWithoutHuman(controller, 0)
    if (success) {
      showToast("Auto without human disabled - you are typing", "info")
      return
    }

    controller.enabledValue = true
    updateButtonUI(controller, true, controller.defaultRoundsValue)
  })
}

async function applyAutoWithoutHuman(controller, rounds, { button = null, enabledRounds = null } = {}) {
  const roundsWhenEnabled = enabledRounds ?? rounds
  const roundsWhenDisabled = controller.defaultRoundsValue

  await withRequestLock(controller.urlValue, async () => {
    const run = async () => {
      const enabling = rounds > 0

      controller.enabledValue = enabling
      updateButtonUI(controller, enabling, enabling ? roundsWhenEnabled : roundsWhenDisabled)

      const success = await toggleAutoWithoutHuman(controller, rounds)
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

  await applyAutoWithoutHuman(controller, controller.defaultRoundsValue, { button })
}

export async function stop(controller, event) {
  event.preventDefault()

  const button = event.currentTarget || (controller.hasButtonTarget ? controller.buttonTarget : null)

  await applyAutoWithoutHuman(controller, 0, { button })
}
