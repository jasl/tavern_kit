import { Controller } from "@hotwired/stimulus"

/**
 * Chat hotkeys controller for keyboard shortcuts in chat conversations.
 *
 * Implements SillyTavern-style hotkeys:
 * - ArrowLeft/ArrowRight: Swipe through AI response versions (disabled when textarea has content)
 * - Ctrl+Enter: Regenerate last AI response
 * - ArrowUp: Edit last message sent by current user (when textarea is empty and focused)
 * - Ctrl+ArrowUp: Edit last user-role message sent by current user
 * - Escape: Cancel any open inline edit
 *
 * @example HTML structure
 *   <div data-controller="chat-hotkeys"
 *        data-chat-hotkeys-conversation-value="123"
 *        data-chat-hotkeys-regenerate-url-value="/conversations/123/regenerate"
 *        data-chat-hotkeys-current-membership-id-value="456">
 *     <textarea data-chat-hotkeys-target="textarea"></textarea>
 *     <div id="messages_list_conversation_123">...</div>
 *   </div>
 */
export default class extends Controller {
  static targets = ["textarea"]
  static values = {
    conversation: Number,
    regenerateUrl: String,
    currentMembershipId: Number
  }

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleKeydown)
  }

  handleKeydown(event) {
    // Escape: Cancel any open inline edit
    if (event.key === "Escape") {
      if (this.cancelAnyOpenEdit()) {
        event.preventDefault()
        return
      }
    }

    // Ctrl+Enter: Regenerate last AI response
    if (event.key === "Enter" && event.ctrlKey && !event.shiftKey && !event.altKey && !event.metaKey) {
      event.preventDefault()
      this.regenerateLastAssistant()
      return
    }

    // Ctrl+ArrowUp: Edit last user-role message sent by current user
    if (event.key === "ArrowUp" && event.ctrlKey && !event.altKey && !event.metaKey && !event.shiftKey) {
      if (this.shouldHandleEditHotkey()) {
        event.preventDefault()
        this.editLastUserMessage()
        return
      }
    }

    // ArrowUp (no modifiers): Edit last message sent by current user
    if (event.key === "ArrowUp" && !event.ctrlKey && !event.altKey && !event.metaKey && !event.shiftKey) {
      if (this.shouldHandleEditHotkey()) {
        event.preventDefault()
        this.editLastOwnMessage()
        return
      }
    }

    // ArrowLeft/ArrowRight: Swipe through versions
    // Disabled when textarea has content (per SillyTavern behavior)
    if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
      // Don't intercept if user is in an input field (other than our textarea)
      const activeElement = document.activeElement
      const isInInput = activeElement && (
        activeElement.tagName === "INPUT" ||
        (activeElement.tagName === "TEXTAREA" && activeElement !== this.textareaTarget)
      )
      if (isInInput) return

      // Disable swipe hotkeys when textarea has content
      if (this.hasTextareaTarget && this.textareaTarget.value.trim().length > 0) {
        return
      }

      // Don't intercept if modifier keys are pressed
      if (event.ctrlKey || event.altKey || event.metaKey || event.shiftKey) return

      event.preventDefault()
      const direction = event.key === "ArrowLeft" ? "left" : "right"
      this.swipeLastAssistant(direction)
    }
  }

  /**
   * Check if edit hotkey should be handled.
   * Only triggers when textarea is focused and empty.
   * @returns {boolean}
   */
  shouldHandleEditHotkey() {
    if (!this.hasCurrentMembershipIdValue) return false
    if (!this.hasTextareaTarget) return false

    // Only when textarea is focused and empty
    const activeElement = document.activeElement
    if (activeElement !== this.textareaTarget) return false
    if (this.textareaTarget.value.trim().length > 0) return false

    return true
  }

  /**
   * Edit the last message sent by current user (any role).
   */
  editLastOwnMessage() {
    const message = this.findLastOwnMessage()
    if (message) this.triggerEdit(message)
  }

  /**
   * Edit the last user-role message sent by current user.
   */
  editLastUserMessage() {
    const message = this.findLastUserMessage()
    if (message) this.triggerEdit(message)
  }

  /**
   * Find the last message sent by current user (any role).
   * @returns {HTMLElement|null}
   */
  findLastOwnMessage() {
    const container = document.getElementById(`messages_list_conversation_${this.conversationValue}`)
    if (!container) return null

    const messages = container.querySelectorAll("[data-message-participant-id]")
    for (let i = messages.length - 1; i >= 0; i--) {
      const msg = messages[i]
      if (parseInt(msg.dataset.messageParticipantId, 10) === this.currentMembershipIdValue) {
        return msg
      }
    }
    return null
  }

  /**
   * Find the last user-role message sent by current user.
   * @returns {HTMLElement|null}
   */
  findLastUserMessage() {
    const container = document.getElementById(`messages_list_conversation_${this.conversationValue}`)
    if (!container) return null

    const messages = container.querySelectorAll("[data-message-participant-id]")
    for (let i = messages.length - 1; i >= 0; i--) {
      const msg = messages[i]
      if (parseInt(msg.dataset.messageParticipantId, 10) === this.currentMembershipIdValue &&
          msg.dataset.messageRole === "user") {
        return msg
      }
    }
    return null
  }

  /**
   * Trigger inline edit by clicking the Edit link.
   * @param {HTMLElement} messageElement - The message element to edit
   */
  triggerEdit(messageElement) {
    const editLink = messageElement.querySelector("a[href*='/inline_edit']")
    if (editLink) editLink.click()
  }

  /**
   * Cancel any open inline edit.
   * @returns {boolean} true if an edit was cancelled
   */
  cancelAnyOpenEdit() {
    // Find any open inline edit form (has textarea with message-actions controller)
    const editTextarea = document.querySelector(
      "[data-controller='message-actions'] textarea[data-message-actions-target='textarea']"
    )
    if (!editTextarea) return false

    // Find the cancel link in the same form container
    const container = editTextarea.closest("[data-controller='message-actions']")
    const cancelLink = container?.querySelector("a[href*='/messages/'][data-turbo-frame]")
    if (cancelLink) {
      cancelLink.click()
      return true
    }
    return false
  }

  /**
   * Regenerate the last assistant message.
   */
  async regenerateLastAssistant() {
    if (!this.hasRegenerateUrlValue) return

    const lastAssistant = this.findLastAssistantMessage()
    if (!lastAssistant) return

    const messageId = lastAssistant.dataset.messageActionsMessageIdValue

    try {
      const response = await fetch(this.regenerateUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": this.csrfToken,
          "Accept": "text/vnd.turbo-stream.html"
        },
        body: messageId ? `message_id=${messageId}` : ""
      })

      if (!response.ok) {
        console.error("Failed to regenerate:", response.status)
      }
    } catch (error) {
      console.error("Regenerate error:", error)
    }
  }

  /**
   * Swipe the last assistant message left or right.
   * @param {string} direction - "left" or "right"
   */
  async swipeLastAssistant(direction) {
    const lastAssistant = this.findLastAssistantMessage()
    if (!lastAssistant) return

    const messageId = lastAssistant.dataset.messageActionsMessageIdValue
    if (!messageId) return

    // Check if message has swipe navigation (position indicator present)
    const hasSwipes = lastAssistant.querySelector(".tabular-nums")
    if (!hasSwipes) return

    const swipeUrl = `/conversations/${this.conversationValue}/messages/${messageId}/swipe`

    try {
      const response = await fetch(swipeUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": this.csrfToken,
          "Accept": "text/vnd.turbo-stream.html"
        },
        body: `dir=${direction}`
      })

      if (!response.ok && response.status !== 200) {
        // 200 OK with empty body is valid (at boundary)
        console.debug("Swipe response:", response.status)
      }
    } catch (error) {
      console.error("Swipe error:", error)
    }
  }

  /**
   * Find the last assistant message element in the chat.
   * @returns {HTMLElement|null}
   */
  findLastAssistantMessage() {
    const messagesContainer = document.getElementById(`messages_list_conversation_${this.conversationValue}`)
    if (!messagesContainer) return null

    // Find all message elements and get the last assistant one
    const messages = messagesContainer.querySelectorAll("[data-controller='message-actions']")
    for (let i = messages.length - 1; i >= 0; i--) {
      const message = messages[i]
      // Check if it's a chat-start (AI character) message
      if (message.classList.contains("chat-start")) {
        return message
      }
    }
    return null
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
