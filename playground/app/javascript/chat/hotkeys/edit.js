import { readMessageMeta } from "../dom"
import { getMessagesContainer, getTailMessageElement } from "./tail"

export function shouldHandleEditHotkey(controller) {
  if (!controller.hasCurrentMembershipIdValue) return false
  if (!controller.hasTextareaTarget) return false

  // Only when textarea is focused and empty
  const activeElement = document.activeElement
  if (activeElement !== controller.textareaTarget) return false
  if (controller.textareaTarget.value.trim().length > 0) return false

  return true
}

export function editLastOwnMessage(controller) {
  const message = findLastOwnMessage(controller)
  if (message) triggerEdit(message)
}

export function editLastUserMessage(controller) {
  const message = findLastUserMessage(controller)
  if (message) triggerEdit(message)
}

export function findLastOwnMessage(controller) {
  const container = getMessagesContainer(controller)
  if (!container) return null

  const tail = getTailMessageElement(controller)
  if (!tail) return null

  const meta = readMessageMeta(tail)
  if (meta?.participantIdInt !== controller.currentMembershipIdValue) {
    // Tail is not owned by current user - cannot edit
    return null
  }

  return tail
}

export function findLastUserMessage(controller) {
  const container = getMessagesContainer(controller)
  if (!container) return null

  const tail = getTailMessageElement(controller)
  if (!tail) return null

  const meta = readMessageMeta(tail)
  if (meta?.participantIdInt !== controller.currentMembershipIdValue) {
    return null
  }
  if (meta?.role !== "user") {
    return null
  }

  return tail
}

export function triggerEdit(messageElement) {
  const editLink = messageElement.querySelector("a[href*='/inline_edit']")
  if (editLink) editLink.click()
}

export function cancelAnyOpenEdit() {
  // Find any open inline edit form (has textarea with message-actions controller)
  const editTextarea = document.querySelector(
    "[data-controller='message-actions'] textarea[data-message-actions-target='textarea']"
  )
  if (!editTextarea) return false

  // Find the cancel link in the same form container
  const container = editTextarea.closest("[data-controller='message-actions']")
  const cancelLink = container?.querySelector("a[href*='/messages/'][data-turbo-frame]")
  if (cancelLink) {
    cancelLink.click()
    return true
  }

  return false
}
