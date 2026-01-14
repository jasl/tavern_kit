import { AUTO_MODE_DISABLED_EVENT, USER_TYPING_DISABLE_AUTO_MODE_EVENT } from "../events"
import { handleAutoModeDisabled, handleUserTypingDisable } from "./actions"

export function bindAutoModeEvents(controller) {
  const onUserTypingDisable = () => handleUserTypingDisable(controller)
  const onAutoModeDisabled = (event) => handleAutoModeDisabled(controller, event)

  window.addEventListener(USER_TYPING_DISABLE_AUTO_MODE_EVENT, onUserTypingDisable)
  window.addEventListener(AUTO_MODE_DISABLED_EVENT, onAutoModeDisabled)

  return () => {
    window.removeEventListener(USER_TYPING_DISABLE_AUTO_MODE_EVENT, onUserTypingDisable)
    window.removeEventListener(AUTO_MODE_DISABLED_EVENT, onAutoModeDisabled)
  }
}
