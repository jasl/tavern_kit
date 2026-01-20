import { AUTO_WITHOUT_HUMAN_DISABLED_EVENT, USER_TYPING_DISABLE_AUTO_WITHOUT_HUMAN_EVENT } from "../events"
import { handleAutoWithoutHumanDisabled, handleUserTypingDisable } from "./actions"

export function bindAutoWithoutHumanEvents(controller) {
  const onUserTypingDisable = () => handleUserTypingDisable(controller)
  const onAutoWithoutHumanDisabled = (event) => handleAutoWithoutHumanDisabled(controller, event)

  window.addEventListener(USER_TYPING_DISABLE_AUTO_WITHOUT_HUMAN_EVENT, onUserTypingDisable)
  window.addEventListener(AUTO_WITHOUT_HUMAN_DISABLED_EVENT, onAutoWithoutHumanDisabled)

  return () => {
    window.removeEventListener(USER_TYPING_DISABLE_AUTO_WITHOUT_HUMAN_EVENT, onUserTypingDisable)
    window.removeEventListener(AUTO_WITHOUT_HUMAN_DISABLED_EVENT, onAutoWithoutHumanDisabled)
  }
}
