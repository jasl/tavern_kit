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
