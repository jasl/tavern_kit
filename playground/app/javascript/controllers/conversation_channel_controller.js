import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"

/**
 * Conversation Channel Controller
 *
 * Unified controller for conversation-level JSON events from ConversationChannel:
 * - typing_start: Show typing indicator with correct styling
 * - typing_stop: Hide typing indicator
 * - stream_chunk: Update typing indicator with streaming content
 * - stream_complete: Signal generation is complete
 * - run_skipped: Show warning toast when a run was skipped (e.g., due to state change)
 * - run_canceled: Show info toast when a run was canceled by the user
 * - run_failed: Show error toast when a run failed with an error
 *
 * All DOM updates for messages go through Turbo Streams separately.
 * This controller only handles the typing indicator and streaming preview.
 */
export default class extends Controller {
  static targets = ["typingIndicator", "typingName", "typingContent", "typingAvatarImg", "typingBubble"]
  static values = {
    conversation: Number,
    timeout: { type: Number, default: 60000 } // Auto-hide after 60s (failsafe)
  }

  connect() {
    this.subscribeToChannel()
    this.timeoutId = null
    this.currentSpaceMembershipId = null
  }

  disconnect() {
    this.unsubscribeFromChannel()
    this.clearTimeout()
  }

  /**
   * Subscribe to ConversationChannel for all JSON events.
   */
  async subscribeToChannel() {
    const conversationId = this.conversationValue
    if (!conversationId) return

    try {
      this.channel = await cable.subscribeTo(
        { channel: "ConversationChannel", conversation_id: conversationId },
        { received: this.handleMessage.bind(this) }
      )
    } catch (error) {
      console.warn("Failed to subscribe to ConversationChannel:", error)
    }
  }

  unsubscribeFromChannel() {
    this.channel?.unsubscribe()
    this.channel = null
  }

  /**
   * Handle incoming ActionCable messages.
   */
  handleMessage(data) {
    if (!data || !data.type) return

    switch (data.type) {
      case "typing_start":
        this.showTypingIndicator(data)
        break
      case "typing_stop":
        this.hideTypingIndicator(data.space_membership_id)
        break
      case "stream_chunk":
        this.updateTypingContent(data.content, data.space_membership_id)
        break
      case "stream_complete":
        this.handleStreamComplete(data.space_membership_id)
        break
      case "run_skipped":
        this.handleRunSkipped(data.reason, data.message)
        break
      case "run_canceled":
        this.handleRunCanceled()
        break
      case "run_failed":
        this.handleRunFailed(data.code, data.message)
        break
    }
  }

  /**
   * Show the typing indicator with correct styling.
   */
  showTypingIndicator(data) {
    const {
      name = "AI",
      space_membership_id: spaceMembershipId,
      is_user: isUser,
      avatar_url: avatarUrl,
      bubble_class: bubbleClass
    } = data

    this.currentSpaceMembershipId = spaceMembershipId

    if (this.hasTypingNameTarget) {
      this.typingNameTarget.textContent = name
    }

    if (this.hasTypingContentTarget) {
      this.typingContentTarget.textContent = ""
    }

    if (this.hasTypingIndicatorTarget) {
      this.typingIndicatorTarget.classList.remove("chat-start", "chat-end")
      this.typingIndicatorTarget.classList.add(isUser ? "chat-end" : "chat-start")
      this.typingIndicatorTarget.classList.remove("hidden")
    }

    if (this.hasTypingAvatarImgTarget && avatarUrl) {
      this.typingAvatarImgTarget.src = avatarUrl
      this.typingAvatarImgTarget.alt = name
    }

    if (this.hasTypingBubbleTarget && bubbleClass) {
      this.typingBubbleTarget.classList.remove(
        "chat-bubble-primary",
        "chat-bubble-secondary",
        "chat-bubble-accent",
        "chat-bubble-neutral",
        "chat-bubble-info",
        "chat-bubble-success",
        "chat-bubble-warning",
        "chat-bubble-error"
      )
      this.typingBubbleTarget.classList.add(bubbleClass)
    }

    this.resetTimeout()
    this.scrollToTypingIndicator()
  }

  /**
   * Hide the typing indicator.
   */
  hideTypingIndicator(participantId = null) {
    if (participantId && this.currentSpaceMembershipId && participantId !== this.currentSpaceMembershipId) {
      return
    }

    if (this.hasTypingIndicatorTarget) {
      this.typingIndicatorTarget.classList.add("hidden")
    }

    if (this.hasTypingContentTarget) {
      this.typingContentTarget.textContent = ""
    }

    this.currentSpaceMembershipId = null
    this.clearTimeout()
  }

  /**
   * Update the typing indicator with streaming content.
   */
  updateTypingContent(content, participantId = null) {
    if (participantId && this.currentSpaceMembershipId && participantId !== this.currentSpaceMembershipId) {
      return
    }

    if (this.hasTypingContentTarget && typeof content === "string") {
      this.typingContentTarget.textContent = content
    }

    this.resetTimeout()
    this.scrollToTypingIndicator()
  }

  /**
   * Handle stream completion.
   * The actual message will appear via Turbo Streams.
   */
  handleStreamComplete(participantId = null) {
    setTimeout(() => {
      this.hideTypingIndicator(participantId)
    }, 100)
  }

  /**
   * Handle run skipped event.
   * Shows a warning toast when a run was skipped (e.g., due to state change).
   */
  handleRunSkipped(reason, message = null) {
    const toastMessage = message || this.getSkippedReasonMessage(reason)
    this.showToast(toastMessage, "warning")
  }

  /**
   * Handle run canceled event.
   * Shows an info toast when generation was stopped by the user.
   */
  handleRunCanceled() {
    this.showToast("Stopped.", "info")
  }

  /**
   * Handle run failed event.
   * Shows an error toast with the failure message.
   */
  handleRunFailed(code, message) {
    const toastMessage = message || "Generation failed. Please try again."
    this.showToast(toastMessage, "error")
  }

  /**
   * Get a user-friendly message for a skip reason code.
   */
  getSkippedReasonMessage(reason) {
    const messages = {
      "message_mismatch": "Skipped: conversation has changed since your request.",
      "state_changed": "Skipped: conversation state changed.",
    }
    return messages[reason] || "Operation skipped due to a state change."
  }

  resetTimeout() {
    this.clearTimeout()
    this.timeoutId = setTimeout(() => {
      this.hideTypingIndicator()
    }, this.timeoutValue)
  }

  clearTimeout() {
    if (this.timeoutId) {
      clearTimeout(this.timeoutId)
      this.timeoutId = null
    }
  }

  scrollToTypingIndicator() {
    const messagesContainer = this.element.closest("[data-chat-scroll-target='messages']")
      || document.querySelector("[data-chat-scroll-target='messages']")

    if (messagesContainer) {
      requestAnimationFrame(() => {
        messagesContainer.scrollTo({
          top: messagesContainer.scrollHeight,
          behavior: "smooth"
        })
      })
    }
  }

  /**
   * Show a toast notification.
   *
   * @param {string} message - The message to display
   * @param {string} type - The toast type: "info", "success", "warning", or "error"
   * @param {number} duration - Duration in milliseconds before auto-dismiss (default: 5000)
   */
  showToast(message, type = "info", duration = 5000) {
    const alertClass = {
      info: "alert-info",
      success: "alert-success",
      warning: "alert-warning",
      error: "alert-error"
    }[type] || "alert-info"

    const iconSvg = this.getToastIcon(type)

    const toast = document.createElement("div")
    toast.className = "toast toast-top toast-end z-50"
    toast.innerHTML = `
      <div class="alert ${alertClass} shadow-lg">
        ${iconSvg}
        <span>${this.escapeHtml(message)}</span>
      </div>
    `

    document.body.appendChild(toast)

    // Auto-remove after duration
    setTimeout(() => {
      toast.remove()
    }, duration)
  }

  /**
   * Get the appropriate SVG icon for a toast type.
   */
  getToastIcon(type) {
    const icons = {
      info: `<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="stroke-current shrink-0 w-6 h-6"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path></svg>`,
      success: `<svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>`,
      warning: `<svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg>`,
      error: `<svg xmlns="http://www.w3.org/2000/svg" class="stroke-current shrink-0 h-6 w-6" fill="none" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>`
    }
    return icons[type] || icons.info
  }

  /**
   * Escape HTML to prevent XSS when inserting user-provided content.
   */
  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
