export function connect(controller) {
  if (!controller.hasSwipesValue) return

  controller.handleTouchStart = controller.handleTouchStart.bind(controller)
  controller.handleTouchMove = controller.handleTouchMove.bind(controller)
  controller.handleTouchEnd = controller.handleTouchEnd.bind(controller)

  controller.element.addEventListener("touchstart", controller.handleTouchStart, { passive: true })
  controller.element.addEventListener("touchmove", controller.handleTouchMove, { passive: true })
  controller.element.addEventListener("touchend", controller.handleTouchEnd, { passive: true })
}

export function disconnect(controller) {
  controller.element.removeEventListener("touchstart", controller.handleTouchStart)
  controller.element.removeEventListener("touchmove", controller.handleTouchMove)
  controller.element.removeEventListener("touchend", controller.handleTouchEnd)
}

