export function bindKeyboardShortcuts(controller) {
  controller.handleKeydown = controller.handleKeydown.bind(controller)
  document.addEventListener("keydown", controller.handleKeydown)
}

export function unbindKeyboardShortcuts(controller) {
  document.removeEventListener("keydown", controller.handleKeydown)
}

export function handleKeydown(controller, event) {
  if (event.target.matches("input, textarea, select, [contenteditable]")) {
    const isChatTextarea = event.target.id === "message_content"
    const isTextareaEmpty = event.target.value?.trim().length === 0
    const isSidebarKey = event.key === "[" || event.key === "]"

    if (!(isChatTextarea && isTextareaEmpty && isSidebarKey)) {
      return
    }
  }

  if (event.key === "[" && controller.keyValue === "left") {
    event.preventDefault()
    controller.toggle()
  } else if (event.key === "]" && controller.keyValue === "right") {
    event.preventDefault()
    controller.toggle()
  }
}

