import { getCableConnected } from "../../conversation_state"

function matchesConversationEvent(controller, event) {
  const eventConversationId = Number(event?.detail?.conversationId)
  if (!eventConversationId) return true
  if (!controller.hasConversationIdValue) return true
  return controller.conversationIdValue === eventConversationId
}

export function handleSchedulingStateChanged(controller, event) {
  if (!matchesConversationEvent(controller, event)) return

  if (event.detail?.schedulingState) {
    controller.schedulingStateValue = event.detail.schedulingState
  }

  if (event.detail?.rejectPolicy !== undefined) {
    controller.rejectPolicyValue = !!event.detail.rejectPolicy
  }
}

export function handleCableConnected(controller, event) {
  if (!matchesConversationEvent(controller, event)) return
  controller.cableConnectedValue = true
}

export function handleCableDisconnected(controller, event) {
  if (!matchesConversationEvent(controller, event)) return
  controller.cableConnectedValue = false
}

export function syncCableConnectedFromGlobalState(controller) {
  if (!controller.hasConversationIdValue) return

  const connected = getCableConnected(controller.conversationIdValue)
  if (connected === false) {
    controller.cableConnectedValue = false
  }
}
