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
