import { findMessagesList } from "../dom"

export function setupMessagesObserver(controller) {
  const list = findMessagesList(controller.element, controller.conversationValue)
  if (!list) return

  controller.messagesObserver = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      if (mutation.type !== "childList" || mutation.addedNodes.length === 0) continue

      // Only react to appends at the end of the list.
      // (Prepending older history for infinite scroll should not clear the indicator.)
      if (mutation.nextSibling !== null) continue

      const appendedMessage = Array.from(mutation.addedNodes).some((node) => {
        return node.nodeType === Node.ELEMENT_NODE
          && typeof node.id === "string"
          && node.id.startsWith("message_")
      })

      if (appendedMessage) {
        controller.hideTypingIndicator()
        controller.hideRunErrorAlert()
        break
      }
    }
  })

  controller.messagesObserver.observe(list, {
    childList: true,
    subtree: false
  })
}

export function disconnectMessagesObserver(controller) {
  if (controller.messagesObserver) {
    controller.messagesObserver.disconnect()
    controller.messagesObserver = null
  }
}
