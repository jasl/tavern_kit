import logger from "../../logger"
import { subscribeToChannel, unsubscribe } from "../cable_subscription"

export async function subscribeToAutoChannel(controller) {
  const match = controller.urlValue.match(/(?:playgrounds|spaces)\/(\d+)/)
  if (!match) return

  controller.spaceId = parseInt(match[1], 10)

  if (!controller.membershipIdValue) {
    logger.warn("AutoChannel: no membership_id, skipping subscription")
    return
  }

  controller.channel = await subscribeToChannel(
    {
      channel: "AutoChannel",
      space_id: controller.spaceId,
      space_membership_id: controller.membershipIdValue
    },
    { received: controller.handleMessage.bind(controller) },
    { label: "AutoChannel" }
  )
}

export function unsubscribeFromAutoChannel(controller) {
  unsubscribe(controller.channel)
  controller.channel = null
}
