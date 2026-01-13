import { cable } from "@hotwired/turbo-rails"
import logger from "../logger"

export async function subscribeToChannel(channelParams, callbacks, options = {}) {
  const { label = "ActionCable" } = options || {}

  try {
    return await cable.subscribeTo(channelParams, callbacks)
  } catch (error) {
    logger.warn(`[cable_subscription] Failed to subscribe (${label}):`, error)
    return null
  }
}

export function unsubscribe(subscription) {
  subscription?.unsubscribe()
}
