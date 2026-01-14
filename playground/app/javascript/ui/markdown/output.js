export function setOutput(controller, html) {
  if (controller.hasOutputTarget) {
    controller.outputTarget.innerHTML = html
    return
  }

  if (controller.hasContentTarget) {
    let output = controller.contentTarget.nextElementSibling
    if (!output || !output.classList.contains("markdown-output")) {
      output = document.createElement("div")
      output.classList.add("markdown-output", "prose", "prose-sm", "max-w-none")
      controller.contentTarget.after(output)
    }
    output.innerHTML = html
    controller.contentTarget.classList.add("hidden")
    return
  }

  controller.element.innerHTML = html
}
