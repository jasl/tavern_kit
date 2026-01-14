export function updateCharCount(controller) {
  if (!controller.hasCharCountTarget || !controller.hasContentTarget) return

  const count = controller.contentTarget.value.length
  controller.charCountTarget.textContent = `${count} chars`
}
