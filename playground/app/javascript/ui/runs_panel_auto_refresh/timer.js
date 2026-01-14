export function startAutoRefresh(controller) {
  stopAutoRefresh(controller)

  controller.refreshTimer = setInterval(() => {
    controller.refreshPanel()
  }, controller.intervalValue)
}

export function stopAutoRefresh(controller) {
  if (controller.refreshTimer) {
    clearInterval(controller.refreshTimer)
    controller.refreshTimer = null
  }
}

