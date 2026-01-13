import { hideEmptyState, showNewIndicator } from "./indicators"

export function observeNewMessages(controller) {
  if (!controller.hasListTarget) return () => {}

  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      if (mutation.type === "childList" && mutation.addedNodes.length > 0) {
        handleNewMessages(controller, mutation.addedNodes)
      }
    }
  })

  observer.observe(controller.listTarget, {
    childList: true,
    subtree: false
  })

  return () => observer.disconnect()
}

function handleNewMessages(controller, nodes) {
  if (controller.loadingValue) return

  const hasNewMessage = Array.from(nodes).some(node =>
    node.nodeType === Node.ELEMENT_NODE
    && node.classList?.contains("mes")
    && typeof node.id === "string"
    && node.id.startsWith("message_")
  )

  if (!hasNewMessage) return

  hideEmptyState(controller)

  if (controller.autoScrollValue) {
    clearTimeout(controller.scrollDebounceTimer)
    controller.scrollDebounceTimer = setTimeout(() => {
      controller.messagesTarget.scrollTop = controller.messagesTarget.scrollHeight
      controller.autoScrollValue = true
    }, 100)
  } else {
    showNewIndicator(controller)
  }
}
