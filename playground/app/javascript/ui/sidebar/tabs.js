export function openTab(controller, tabName) {
  if (!tabName) return

  controller.open()

  requestAnimationFrame(() => {
    const tabsElement = controller.element.querySelector("[data-controller~='tabs']")
    if (!tabsElement) return

    const tabButton = tabsElement.querySelector(`[data-tab="${tabName}"]`)
    tabButton?.click()
  })
}
