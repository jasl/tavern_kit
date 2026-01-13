const MESSAGE_LIST_REGISTRY = new WeakMap()
const MESSAGE_LIST_UPDATE_DEBOUNCE_MS = 50

function scheduleListUpdate(registry) {
  if (registry.updateTimeout) clearTimeout(registry.updateTimeout)

  registry.updateTimeout = setTimeout(() => {
    registry.updateTimeout = null

    for (const controller of registry.controllers) {
      if (!controller.element?.isConnected) continue
      controller.updateButtonVisibility()
    }
  }, MESSAGE_LIST_UPDATE_DEBOUNCE_MS)
}

function getMessageListRegistry(list) {
  const existing = MESSAGE_LIST_REGISTRY.get(list)
  if (existing) return existing

  const registry = {
    controllers: new Set(),
    updateTimeout: null,
    observer: null
  }

  registry.observer = new MutationObserver((mutations) => {
    const hasChildChanges = mutations.some((mutation) => {
      return mutation.type === "childList" && (mutation.addedNodes.length > 0 || mutation.removedNodes.length > 0)
    })

    const hasAttrChanges = mutations.some((mutation) => {
      return mutation.type === "attributes" && mutation.attributeName === "data-tail-message-id"
    })

    if (!hasChildChanges && !hasAttrChanges) return

    scheduleListUpdate(registry)
  })

  registry.observer.observe(list, {
    childList: true,
    subtree: false,
    attributes: true,
    attributeFilter: ["data-tail-message-id"]
  })

  MESSAGE_LIST_REGISTRY.set(list, registry)
  return registry
}

export function registerListObserver(controller, list) {
  if (!list) return

  controller.messageList = list
  controller.messageListRegistry = getMessageListRegistry(list)
  controller.messageListRegistry.controllers.add(controller)
}

export function unregisterListObserver(controller) {
  if (!controller.messageListRegistry || !controller.messageList) return

  controller.messageListRegistry.controllers.delete(controller)

  if (controller.messageListRegistry.controllers.size === 0) {
    controller.messageListRegistry.observer?.disconnect()
    if (controller.messageListRegistry.updateTimeout) clearTimeout(controller.messageListRegistry.updateTimeout)
    MESSAGE_LIST_REGISTRY.delete(controller.messageList)
  }

  controller.messageList = null
  controller.messageListRegistry = null
}
