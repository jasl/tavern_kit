import { findMessagesList, findTailMessage } from "../dom"

/**
 * Get the messages list container element.
 * @returns {HTMLElement|null}
 */
export function getMessagesContainer(controller) {
  return findMessagesList(controller.element, controller.conversationValue)
}

/**
 * Get the tail (last) message element in the conversation.
 * @returns {HTMLElement|null}
 */
export function getTailMessageElement(controller) {
  return findTailMessage(getMessagesContainer(controller))
}

/**
 * Check if the tail message is an assistant that can be regenerated.
 * @returns {boolean}
 */
export function canRegenerateTail(controller) {
  if (!controller.hasRegenerateUrlValue) return false
  const tail = getTailMessageElement(controller)
  if (!tail) return false
  return tail.dataset.messageRole === "assistant"
}

/**
 * Check if the tail message is an assistant with swipes.
 * @returns {boolean}
 */
export function canSwipeTail(controller) {
  const tail = getTailMessageElement(controller)
  if (!tail) return false
  return tail.dataset.messageRole === "assistant" && tail.dataset.messageHasSwipes === "true"
}
