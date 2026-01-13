import { isAtBottom } from "./bottom"
import { hideNewIndicator } from "./indicators"

export function bindScrollEvents(controller) {
  if (!controller.hasMessagesTarget) return () => {}

  const onScroll = () => {
    controller.autoScrollValue = isAtBottom(controller)

    if (controller.autoScrollValue) {
      hideNewIndicator(controller)
    }
  }

  controller.messagesTarget.addEventListener("scroll", onScroll, { passive: true })

  return () => {
    controller.messagesTarget.removeEventListener("scroll", onScroll)
  }
}
