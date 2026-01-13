export function handleEditKeydown(controller, event) {
  if (event.key === "Escape") {
    event.preventDefault()
    controller.cancelEdit()
  }

  if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
    event.preventDefault()
    const form = event.target.closest("form")
    if (form) {
      form.requestSubmit()
    }
  }
}

export function cancelEdit(controller) {
  const cancelLink = controller.element.querySelector("[data-action*='cancel']")
    || controller.element.querySelector("a.btn-ghost")

  if (cancelLink) {
    cancelLink.click()
  }
}

export function handleEscape(controller, event) {
  if (event.key === "Escape" && controller.editingValue) {
    controller.cancelEdit()
  }
}

