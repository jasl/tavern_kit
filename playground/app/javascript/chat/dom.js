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
