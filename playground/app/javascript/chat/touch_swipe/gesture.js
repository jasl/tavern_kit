export function handleTouchStart(controller, event) {
  if (event.touches.length !== 1) return

  const touch = event.touches[0]
  controller.touchStartX = touch.clientX
  controller.touchStartY = touch.clientY
  controller.touchStartTime = Date.now()
  controller.isSwiping = false
}

export function handleTouchMove(controller, event) {
  if (event.touches.length !== 1) return

  const touch = event.touches[0]
  const deltaX = touch.clientX - controller.touchStartX
  const deltaY = touch.clientY - controller.touchStartY

  if (Math.abs(deltaX) > 20 && Math.abs(deltaX) > Math.abs(deltaY) * 1.5) {
    controller.isSwiping = true
  }
}

export function handleTouchEnd(controller, event) {
  const touch = event.changedTouches[0]
  const deltaX = touch.clientX - controller.touchStartX
  const deltaY = touch.clientY - controller.touchStartY
  const deltaTime = Date.now() - controller.touchStartTime

  controller.isSwiping = false

  if (!isValidSwipe(controller, deltaX, deltaY, deltaTime)) return null

  return deltaX > 0 ? "left" : "right"
}

export function isValidSwipe(controller, deltaX, deltaY, deltaTime) {
  if (Math.abs(deltaX) < controller.minSwipeDistance) return false
  if (Math.abs(deltaY) > controller.maxVerticalDistance) return false
  if (deltaTime > controller.maxSwipeTime) return false
  if (Math.abs(deltaY) >= Math.abs(deltaX)) return false

  return true
}

