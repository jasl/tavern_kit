import logger from "../../logger"
import { turboRequest } from "../../request_helpers"
import { CABLE_CONNECTED_EVENT, CABLE_DISCONNECTED_EVENT } from "../events"
import { getLastMessageElement } from "./messages_dom"

const CATCH_UP_MAX_PAGES = 5

export function bindCableSync(controller) {
  const onConnected = (event) => handleCableConnected(controller, event)
  const onDisconnected = (event) => handleCableDisconnected(controller, event)

  window.addEventListener(CABLE_CONNECTED_EVENT, onConnected)
  window.addEventListener(CABLE_DISCONNECTED_EVENT, onDisconnected)

  return () => {
    window.removeEventListener(CABLE_CONNECTED_EVENT, onConnected)
    window.removeEventListener(CABLE_DISCONNECTED_EVENT, onDisconnected)
  }
}

function conversationId(controller) {
  const id = Number(controller.element.dataset.conversationChannelConversationValue)
  return Number.isFinite(id) && id > 0 ? id : null
}

function shouldHandleCableEvent(controller, event) {
  const myId = conversationId(controller)
  const theirId = Number(event?.detail?.conversationId)

  if (!myId || !theirId) return true
  return myId === theirId
}

function handleCableDisconnected(controller, event) {
  if (!shouldHandleCableEvent(controller, event)) return
  controller.wasDisconnected = true
}

function handleCableConnected(controller, event) {
  if (!shouldHandleCableEvent(controller, event)) return
  if (event?.detail?.reconnected !== true) return

  controller.wasDisconnected = false
  syncNewMessages(controller)
}

export async function syncNewMessages(controller, { maxPages = CATCH_UP_MAX_PAGES } = {}) {
  if (controller.syncingNewMessages) return
  if (!controller.hasListTarget || !controller.loadMoreUrlValue) return

  const lastMessage = getLastMessageElement(controller)
  if (!lastMessage) return

  controller.syncingNewMessages = true

  let cursorId = lastMessage.id.replace("message_", "")

  try {
    for (let page = 0; page < maxPages; page++) {
      const url = `${controller.loadMoreUrlValue}?after=${encodeURIComponent(cursorId)}`

      const { response, renderedTurboStream, turboStreamHtml } = await turboRequest(url, {
        accept: "text/vnd.turbo-stream.html",
        headers: { "X-Requested-With": "XMLHttpRequest" }
      })

      if (response.status === 204) return
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      if (!renderedTurboStream || !turboStreamHtml?.trim()) return

      const newLastMessage = getLastMessageElement(controller)
      if (!newLastMessage) return

      const nextCursorId = newLastMessage.id.replace("message_", "")
      if (nextCursorId === cursorId) return
      cursorId = nextCursorId
    }
  } catch (error) {
    logger.error("Failed to sync new messages:", error)
  } finally {
    controller.syncingNewMessages = false
  }
}
