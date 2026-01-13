import logger from "../../logger"
import { subscribeToChannel, unsubscribe } from "../cable_subscription"

export async function subscribeToCopilotChannel(controller) {
  const match = controller.urlValue.match(/(?:playgrounds|spaces)\/(\d+)/)
  if (!match) return

  controller.spaceId = parseInt(match[1], 10)

  if (!controller.membershipIdValue) {
    logger.warn("CopilotChannel: no membership_id, skipping subscription")
    return
  }

  controller.channel = await subscribeToChannel(
    {
      channel: "CopilotChannel",
      space_id: controller.spaceId,
      space_membership_id: controller.membershipIdValue
    },
    { received: controller.handleMessage.bind(controller) },
    { label: "CopilotChannel" }
  )
}

export function unsubscribeFromCopilotChannel(controller) {
  unsubscribe(controller.channel)
  controller.channel = null
}

