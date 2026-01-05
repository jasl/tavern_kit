import { Controller } from "@hotwired/stimulus"

/**
 * Chat hotkeys controller for keyboard shortcuts in chat conversations.
 *
 * Implements SillyTavern-style hotkeys:
 * - ArrowLeft/ArrowRight: Swipe through AI response versions (only when tail is assistant with swipes)
 * - Ctrl+Enter: Regenerate tail AI response (only when tail is assistant)
 * - ArrowUp: Edit last message sent by current user (when textarea is empty and focused)
 * - Ctrl+ArrowUp: Edit last user-role message sent by current user
 * - Escape: Cancel any open inline edit
 *
 * IMPORTANT: Swipe and regenerate hotkeys only operate on the TAIL message.
 * If the tail message is not an assistant, these hotkeys are ignored (key not intercepted).
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

    // Ctrl+Enter: Regenerate tail AI response (only if tail is assistant)
    if (event.key === "Enter" && event.ctrlKey && !event.shiftKey && !event.altKey && !event.metaKey) {
      if (this.canRegenerateTail()) {
        event.preventDefault()
        this.regenerateTailAssistant()
      }
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

    // ArrowLeft/ArrowRight: Swipe through versions (only if tail is assistant with swipes)
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

      // Only preventDefault if tail is assistant with swipes
      if (this.canSwipeTail()) {
        event.preventDefault()
        const direction = event.key === "ArrowLeft" ? "left" : "right"
        this.swipeTailAssistant(direction)
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Tail Message Helpers
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * Get the messages list container element.
   * @returns {HTMLElement|null}
   */
  getMessagesContainer() {
    return document.getElementById(`messages_list_conversation_${this.conversationValue}`)
  }

  /**
   * Get the tail (last) message element in the conversation.
   * @returns {HTMLElement|null}
   */
  getTailMessageElement() {
    const container = this.getMessagesContainer()
    if (!container) return null
    // Get last .chat child (message element)
    return container.querySelector(".chat:last-child")
  }

  /**
   * Check if the tail message is an assistant that can be regenerated.
   * @returns {boolean}
   */
  canRegenerateTail() {
    if (!this.hasRegenerateUrlValue) return false
    const tail = this.getTailMessageElement()
    if (!tail) return false
    return tail.dataset.messageRole === "assistant"
  }

  /**
   * Check if the tail message is an assistant with swipes.
   * @returns {boolean}
   */
  canSwipeTail() {
    const tail = this.getTailMessageElement()
    if (!tail) return false
    return tail.dataset.messageRole === "assistant" && tail.dataset.messageHasSwipes === "true"
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Edit Hotkey Helpers
  // ─────────────────────────────────────────────────────────────────────────────

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
    const container = this.getMessagesContainer()
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
    const container = this.getMessagesContainer()
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

  // ─────────────────────────────────────────────────────────────────────────────
  // Regenerate & Swipe Actions
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * Regenerate the tail assistant message.
   * Does NOT send message_id; the server uses the tail by default.
   */
  async regenerateTailAssistant() {
    if (!this.hasRegenerateUrlValue) return

    try {
      const response = await fetch(this.regenerateUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": this.csrfToken,
          "Accept": "text/vnd.turbo-stream.html"
        },
        body: "" // No message_id - server uses tail
      })

      if (!response.ok) {
        console.error("Failed to regenerate:", response.status)
      }
    } catch (error) {
      console.error("Regenerate error:", error)
    }
  }

  /**
   * Swipe the tail assistant message left or right.
   * Only operates on the tail message (last in conversation).
   * @param {string} direction - "left" or "right"
   */
  async swipeTailAssistant(direction) {
    const tail = this.getTailMessageElement()
    if (!tail) return

    // Double-check tail is assistant with swipes
    if (tail.dataset.messageRole !== "assistant" || tail.dataset.messageHasSwipes !== "true") {
      return
    }

    const messageId = tail.dataset.messageActionsMessageIdValue
    if (!messageId) return

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

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
