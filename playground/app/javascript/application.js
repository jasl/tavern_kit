// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"
import "./custom_turbo_actions"
import logger from "./logger"

// Global toast handler
// Listens for `toast:show` custom events and displays toast notifications.
// Uses the toast template from shared/_js_templates.html.erb for consistent styling.
// This allows any controller or script to show toasts without coupling to a specific controller.
window.addEventListener("toast:show", (event) => {
  const { message, type = "info", duration = 5000 } = event.detail || {}
  if (!message) return

  const template = document.getElementById("toast_template")
  const container = document.getElementById("toast_container")
  if (!template || !container) {
    // Fallback if templates not loaded (shouldn't happen in normal operation)
    logger.warn("[toast] Template or container not found")
    return
  }

  // Clone the template
  const toast = template.content.cloneNode(true).firstElementChild
  if (!toast) return

  // Apply type-specific styling
  const normalizedType = String(type || "info")
  const alertClass = {
    info: "alert-info",
    success: "alert-success",
    notice: "alert-success",
    warning: "alert-warning",
    error: "alert-error",
    alert: "alert-error"
  }[normalizedType] || "alert-info"

  const iconClass = {
    info: "icon-[lucide--info]",
    success: "icon-[lucide--check-circle]",
    notice: "icon-[lucide--check-circle]",
    warning: "icon-[lucide--alert-triangle]",
    error: "icon-[lucide--x-circle]",
    alert: "icon-[lucide--x-circle]"
  }[normalizedType] || "icon-[lucide--info]"

  const alert = toast.querySelector("[data-toast-target='alert']")
  if (alert) alert.classList.add(alertClass)

  const icon = toast.querySelector("[data-toast-icon]")
  if (icon) icon.className = `${iconClass} size-5 shrink-0`

  // Set message text (textContent auto-escapes, preventing XSS)
  toast.querySelector("[data-toast-message]").textContent = message

  toast.dataset.toastDurationValue = String(duration)
  container.appendChild(toast)
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
    logger.debug(`[turbo-dedup] Skipping duplicate: #${firstElement.id}`)
    event.preventDefault()
  }
})
