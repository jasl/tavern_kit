export function setStatus(controller, status) {
  if (!controller.hasStatusTarget) return

  const statusMap = {
    saving: { text: "Saving...", class: "badge-warning" },
    saved: { text: "Saved", class: "badge-success" },
    error: { text: "Error", class: "badge-error" }
  }

  const config = statusMap[status] || { text: "", class: "badge-ghost" }

  controller.statusTarget.textContent = config.text
  controller.statusTarget.className = `badge badge-sm ${config.class}`

  if (status === "saved") {
    setTimeout(() => {
      if (controller.statusTarget.textContent === "Saved") {
        controller.statusTarget.textContent = ""
        controller.statusTarget.className = "badge badge-sm badge-ghost"
      }
    }, 2000)
  }
}

export function setSavedAt(controller, isoString) {
  if (!controller.hasSavedAtTarget) return

  try {
    const date = new Date(isoString)
    controller.savedAtTarget.textContent = `Last saved: ${date.toLocaleTimeString()}`
  } catch {
    controller.savedAtTarget.textContent = ""
  }
}
