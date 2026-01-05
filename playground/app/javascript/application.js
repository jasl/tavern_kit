// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import "./custom_turbo_actions"

// Global toast handler
// Listens for `toast:show` custom events and displays toast notifications.
// Uses the toast template from shared/_js_templates.html.erb for consistent styling.
// This allows any controller or script to show toasts without coupling to a specific controller.
window.addEventListener("toast:show", (event) => {
  const { message, type = "info", duration = 5000 } = event.detail || {}
  if (!message) return

  const template = document.getElementById("toast-template")
  const container = document.getElementById("toast-container")
  if (!template || !container) {
    // Fallback if templates not loaded (shouldn't happen in normal operation)
    console.warn("[toast] Template or container not found")
    return
  }

  // Clone the template
  const toast = template.content.cloneNode(true).firstElementChild

  // Apply type-specific styling
  const alertClass = {
    info: "alert-info",
    success: "alert-success",
    warning: "alert-warning",
    error: "alert-error"
  }[type] || "alert-info"
  toast.classList.add(alertClass)

  // Set message text (textContent auto-escapes, preventing XSS)
  toast.querySelector("[data-toast-message]").textContent = message

  container.appendChild(toast)

  // Auto-dismiss with fade animation
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
