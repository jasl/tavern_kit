export function updateStatus(controller, status, message = null) {
  if (!controller.hasStatusTarget) return

  const statusEl = controller.statusTarget

  statusEl.classList.remove("badge-warning", "badge-info", "badge-success", "badge-error")

  switch (status) {
    case "pending":
      statusEl.classList.add("badge-warning")
      statusEl.textContent = "Unsaved"
      break
    case "saving":
      statusEl.classList.add("badge-info")
      statusEl.textContent = "Saving..."
      break
    case "saved":
      statusEl.classList.add("badge-success")
      statusEl.textContent = "Saved"
      setTimeout(() => {
        if (controller.pendingChanges.size === 0) {
          statusEl.textContent = ""
          statusEl.classList.remove("badge-success")
        }
      }, 2000)
      break
    case "error":
      statusEl.classList.add("badge-error")
      statusEl.textContent = message || "Error"
      break
  }
}
