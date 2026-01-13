import { hideNewIndicator } from "./indicators"

export function isAtBottom(controller) {
  if (!controller.hasMessagesTarget) return true

  const { scrollTop, scrollHeight, clientHeight } = controller.messagesTarget
  const distanceFromBottom = scrollHeight - scrollTop - clientHeight
  return distanceFromBottom <= controller.thresholdValue
}

export function scrollToBottomInstant(controller) {
  if (!controller.hasMessagesTarget) return

  controller.messagesTarget.scrollTop = controller.messagesTarget.scrollHeight
  controller.autoScrollValue = true
  hideNewIndicator(controller)
}

export function scrollToBottom(controller, { smooth = true } = {}) {
  if (!controller.hasMessagesTarget) return

  if (smooth) {
    controller.messagesTarget.scrollTo({
      top: controller.messagesTarget.scrollHeight,
      behavior: "smooth"
    })
    controller.autoScrollValue = true
    hideNewIndicator(controller)
  } else {
    scrollToBottomInstant(controller)
  }
}

export function scrollToMessage(controller, messageId) {
  const message = controller.messagesTarget.querySelector(`#${messageId}`)
  if (message) {
    message.scrollIntoView({ behavior: "smooth", block: "center" })
  }
}
