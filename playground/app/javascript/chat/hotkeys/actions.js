import logger from "../../logger"
import { turboPost } from "../../request_helpers"
import { getTailMessageElement } from "./tail"

export async function stopGeneration(controller) {
  if (!controller.hasStopUrlValue) return

  try {
    const { response } = await turboPost(controller.stopUrlValue)

    if (!response.ok) {
      logger.error("Stop generation failed:", response.status)
    }
  } catch (error) {
    logger.error("Stop generation error:", error)
  }
}

export async function regenerateTailAssistant(controller) {
  if (!controller.hasRegenerateUrlValue) return

  try {
    const { response } = await turboPost(controller.regenerateUrlValue, {
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: "" // No message_id - server uses tail
    })

    if (!response.ok) {
      logger.error("Failed to regenerate:", response.status)
    }
  } catch (error) {
    logger.error("Regenerate error:", error)
  }
}

export async function swipeTailAssistant(controller, direction) {
  const tail = getTailMessageElement(controller)
  if (!tail) return

  // Double-check tail is assistant with swipes
  if (tail.dataset.messageRole !== "assistant" || tail.dataset.messageHasSwipes !== "true") {
    return
  }

  const messageId = tail.dataset.messageActionsMessageIdValue
  if (!messageId) return

  const swipeUrl = `/conversations/${controller.conversationValue}/messages/${messageId}/swipe`

  try {
    const { response } = await turboPost(swipeUrl, {
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `dir=${direction}`
    })

    // 200 OK with empty body is valid (at boundary)
    // Non-2xx status is silently ignored (e.g., at swipe boundary)
    void response
  } catch (error) {
    logger.error("Swipe error:", error)
  }
}
