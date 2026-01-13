import { Turbo } from "@hotwired/turbo-rails"

/**
 * Custom Turbo Stream Actions
 *
 * Extends Turbo Streams with custom actions for modal handling and other UI operations.
 */

// Close a dialog modal by ID
// Usage: <%= turbo_stream.action :close_modal, "modal_id" %>
Turbo.StreamActions.close_modal = function () {
  const targetId = this.getAttribute("target")
  const modal = document.getElementById(targetId)
  if (modal && typeof modal.close === "function") {
    modal.close()
  }
}

// Dispatch a custom event on an element
// Usage: <%= turbo_stream.action :dispatch_event, target: "element_id", event: "custom:event" %>
Turbo.StreamActions.dispatch_event = function () {
  const targetId = this.getAttribute("target")
  const eventName = this.getAttribute("event")
  const element = document.getElementById(targetId)
  if (element && eventName) {
    element.dispatchEvent(new CustomEvent(eventName, { bubbles: true }))
  }
}

// Show a toast notification by appending to the toast container
// Usage: <%= turbo_stream.action :show_toast, nil do %><%= render "shared/toast", message: "Hello" %><% end %>
Turbo.StreamActions.show_toast = function () {
  const template = this.templateContent
  const container = document.getElementById("toast_container")
  if (template && container) {
    container.appendChild(template.cloneNode(true))
  }
}

// Hide the typing indicator + stuck warning (best-effort state reset)
// Usage: <%= turbo_stream.action :hide_typing_indicator %>
Turbo.StreamActions.hide_typing_indicator = function () {
  const typingIndicator = document.getElementById("typing_indicator")
  if (typingIndicator) {
    typingIndicator.classList.add("hidden")
    const content = typingIndicator.querySelector("[data-conversation-channel-target='typingContent']")
    if (content) content.textContent = ""
  }

  const stuckWarning = document.getElementById("stuck_warning")
  if (stuckWarning) {
    stuckWarning.classList.add("hidden")
  }
}
