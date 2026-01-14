export function findMessagesList(root, conversationId = null) {
  if (root) {
    if (typeof root.matches === "function" && root.matches("[data-chat-scroll-target='list']")) {
      return root
    }

    if (typeof root.closest === "function") {
      const list = root.closest("[data-chat-scroll-target='list']")
      if (list) return list
    }

    const list = root.querySelector("[data-chat-scroll-target='list']")
    if (list) return list
  }

  if (conversationId) {
    return document.getElementById(`messages_list_conversation_${conversationId}`)
  }

  return null
}

export function findTailMessage(list) {
  if (!list) return null

  const lastChild = list.lastElementChild
  if (lastChild && lastChild.classList.contains("mes")) return lastChild

  return list.querySelector(".mes:last-child")
}

/**
 * Read the most common message metadata used by chat controllers.
 *
 * This is a small contract between server-rendered message DOM and client behavior:
 * - `data-message-role` ("user" / "assistant") drives tail-only UX rules
 * - `data-message-participant-id` identifies ownership for edit/delete controls
 * - `data-message-has-swipes` enables swipe hotkeys + nav visibility
 * - `data-message-actions-message-id-value` comes from the message-actions controller value
 *
 * @param {HTMLElement|null} messageElement
 * @returns {{
 *   role: string|null,
 *   participantId: string|null,
 *   participantIdInt: number|null,
 *   messageId: string|null,
 *   messageIdInt: number|null,
 *   hasSwipes: boolean
 * }|null}
 */
export function readMessageMeta(messageElement) {
  if (!messageElement) return null

  const role = messageElement.dataset.messageRole || null

  const participantId = messageElement.dataset.messageParticipantId || null
  let participantIdInt = participantId ? Number.parseInt(participantId, 10) : null
  if (Number.isNaN(participantIdInt)) participantIdInt = null

  const messageId = messageElement.dataset.messageActionsMessageIdValue || null
  let messageIdInt = messageId ? Number.parseInt(messageId, 10) : null
  if (Number.isNaN(messageIdInt)) messageIdInt = null

  const hasSwipes = messageElement.dataset.messageHasSwipes === "true"

  return { role, participantId, participantIdInt, messageId, messageIdInt, hasSwipes }
}
