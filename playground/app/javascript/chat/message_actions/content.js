export function getMessageContent(controller) {
  const template = controller.element.querySelector("template[data-markdown-target='content']")
  if (template) {
    return template.content.textContent.trim()
  }

  const output = controller.element.querySelector("[data-markdown-target='output']")
  if (output) {
    return output.textContent.trim()
  }

  const mesText = controller.element.querySelector(".mes-text")
  if (mesText) {
    return mesText.textContent.trim()
  }

  return null
}
