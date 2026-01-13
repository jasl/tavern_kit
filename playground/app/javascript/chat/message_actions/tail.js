import { findMessagesList } from "../dom"

export function findCurrentMembershipId(controller) {
  const container = controller.element.closest("[data-current-membership-id]")
  return container?.dataset.currentMembershipId || null
}

export function findTailMessageId(controller) {
  const container = controller.element.closest("[data-tail-message-id]")
  return container?.dataset.tailMessageId || null
}

export function domTailMessageId(list) {
  if (!list) return null

  const tailElement = list.lastElementChild
  if (!tailElement) return null

  return tailElement.dataset.messageActionsMessageIdValue || null
}

export function setTailMessageId(list, tailMessageId) {
  if (!list) return

  const next = tailMessageId == null ? "" : String(tailMessageId)
  const current = list.dataset.tailMessageId || ""

  if (current === next) return

  list.dataset.tailMessageId = next
}

export function syncTailMessageIdIfIAmTail(controller) {
  const list = findMessagesList(controller.element)
  if (!list) return

  if (list.lastElementChild === controller.element) {
    setTailMessageId(list, controller.messageIdValue)
  }
}

export function isTailMessage(controller) {
  const list = findMessagesList(controller.element)
  const domTail = domTailMessageId(list)

  if (domTail) {
    if (findTailMessageId(controller) !== domTail) {
      setTailMessageId(list, domTail)
    }

    return String(controller.messageIdValue) === domTail
  }

  const tailMessageId = findTailMessageId(controller)
  if (tailMessageId) {
    return String(controller.messageIdValue) === String(tailMessageId)
  }

  if (!list) return false

  const messages = list.querySelectorAll("[data-controller~='message-actions']")
  if (messages.length === 0) return false

  return messages[messages.length - 1] === controller.element
}

