// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"

// Global toast handler
// Listens for `toast:show` custom events and displays toast notifications.
// This allows any controller or script to show toasts without coupling to a specific controller.
window.addEventListener("toast:show", (event) => {
  const { message, type = "info", duration = 5000, html = false } = event.detail || {}
  if (!message) return

  // Find or create toast container
  let container = document.getElementById("toast-container")
  if (!container) {
    container = document.createElement("div")
    container.id = "toast-container"
    container.className = "toast toast-end toast-top z-50"
    document.body.appendChild(container)
  }

  const alertClass = {
    info: "alert-info",
    success: "alert-success",
    warning: "alert-warning",
    error: "alert-error"
  }[type] || "alert-info"

  const toast = document.createElement("div")
  toast.className = `alert ${alertClass} shadow-lg`

  if (html) {
    toast.innerHTML = message
  } else {
    toast.textContent = message
  }

  container.appendChild(toast)

  // Auto-dismiss
  setTimeout(() => {
    toast.style.transition = "opacity 300ms ease-out"
    toast.style.opacity = "0"
    setTimeout(() => toast.remove(), 300)
  }, duration)
})

// Deduplicate Turbo Stream message appends
// Prevents duplicate messages when page render and WebSocket broadcast race
document.addEventListener("turbo:before-stream-render", (event) => {
  const stream = event.target

  // Only handle append/prepend to messages containers
  const action = stream.getAttribute("action")
  if (action !== "append" && action !== "prepend") return

  const target = stream.getAttribute("target")
  if (!target || !target.startsWith("messages_list_conversation_")) return

  // Extract the first element ID from the template
  const template = stream.querySelector("template")
  if (!template) return

  const content = template.content
  const firstElement = content.firstElementChild
  if (!firstElement || !firstElement.id) return

  // If element already exists, skip this stream
  if (document.getElementById(firstElement.id)) {
    console.debug(`[turbo-dedup] Skipping duplicate: #${firstElement.id}`)
    event.preventDefault()
  }
})
