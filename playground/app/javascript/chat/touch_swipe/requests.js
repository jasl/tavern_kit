import logger from "../../logger"
import { turboPost } from "../../request_helpers"

export async function triggerSwipe(controller, direction) {
  if (!controller.hasConversationValue || !controller.hasMessageValue) return

  const swipeUrl = `/conversations/${controller.conversationValue}/messages/${controller.messageValue}/swipe`

  try {
    const { response } = await turboPost(swipeUrl, {
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `dir=${direction}`
    })

    void response
  } catch (error) {
    logger.error("Touch swipe error:", error)
  }
}

