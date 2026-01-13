export function getFirstMessageElement(controller) {
  if (!controller.hasListTarget) return null
  return controller.listTarget.querySelector(".mes[id^='message_']")
}

export function getLastMessageElement(controller) {
  if (!controller.hasListTarget) return null

  let current = controller.listTarget.lastElementChild
  while (current && !(current.id && current.id.startsWith("message_"))) {
    current = current.previousElementSibling
  }

  return current
}
