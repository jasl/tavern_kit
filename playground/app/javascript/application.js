// Entry point for the build script in your package.json
import "@hotwired/turbo-rails"
import "./controllers"

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
