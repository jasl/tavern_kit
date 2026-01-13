const cableConnectedByConversationId = new Map()

function normalizeConversationId(conversationId) {
  const id = Number(conversationId)
  return Number.isFinite(id) && id > 0 ? id : null
}

export function getCableConnected(conversationId) {
  const id = normalizeConversationId(conversationId)
  if (!id) return null
  return cableConnectedByConversationId.get(id) ?? null
}

export function setCableConnected(conversationId, connected) {
  const id = normalizeConversationId(conversationId)
  if (!id) return
  cableConnectedByConversationId.set(id, connected === true)
}

export function clearCableConnected(conversationId) {
  const id = normalizeConversationId(conversationId)
  if (!id) return
  cableConnectedByConversationId.delete(id)
}

