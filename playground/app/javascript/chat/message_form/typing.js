import { USER_TYPING_DISABLE_AUTO_MODE_EVENT, USER_TYPING_DISABLE_COPILOT_EVENT, dispatchWindowEvent } from "../events"

export function handleInput(controller, event) {
  void controller

  // Only dispatch if there's actual content being typed
  if (!event.target.value.trim()) return

  // Dispatch events for other controllers to handle
  // Using window-level events for cross-controller communication
  dispatchWindowEvent(USER_TYPING_DISABLE_COPILOT_EVENT, null, { cancelable: true })
  dispatchWindowEvent(USER_TYPING_DISABLE_AUTO_MODE_EVENT, null, { cancelable: true })
}
