import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { fetchTurboStream } from "../turbo_fetch"

/**
 * Chat hotkeys controller for keyboard shortcuts in chat conversations.
 *
 * Implements SillyTavern-style hotkeys:
 * - ArrowLeft/ArrowRight: Swipe through AI response versions (only when tail is assistant with swipes)
 * - Ctrl+Enter: Regenerate tail AI response (only when tail is assistant)
 * - ArrowUp: Edit last message sent by current user (when textarea is empty and focused)
 * - Ctrl+ArrowUp: Edit last user-role message sent by current user
 * - Escape: Cancel any open inline edit, or stop generation if no edit is open
 * - ?: Show hotkeys help modal (when not in input field)
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
    stopUrl: String,
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
    // IME protection: don't intercept during composition (e.g., CJK input)
    if (event.isComposing) return

    // Escape: Cancel any open inline edit, or stop generation
    if (event.key === "Escape") {
      if (this.cancelAnyOpenEdit()) {
        event.preventDefault()
        return
      }
      // No inline edit open - stop generation
      if (this.hasStopUrlValue) {
        event.preventDefault()
        this.stopGeneration()
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

    // ?: Show hotkeys help modal (when not in input field)
    if (event.key === "?") {
      // Don't intercept if user is in any input field
      const activeElement = document.activeElement
      const isInInput = activeElement && (
        activeElement.tagName === "INPUT" ||
        activeElement.tagName === "TEXTAREA" ||
        activeElement.isContentEditable
      )
      if (isInInput) return

      event.preventDefault()
      this.showHotkeysHelpModal()
    }

    // Note: [ and ] sidebar toggles are handled by sidebar_controller.js
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
    // Get last .mes child (SillyTavern-style message element)
    return container.querySelector(".mes:last-child")
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
   * Find the last message sent by current user (any role), but ONLY if it's the tail.
   * This prevents attempting to edit non-tail messages which the server will reject.
   * @returns {HTMLElement|null}
   */
  findLastOwnMessage() {
    const container = this.getMessagesContainer()
    if (!container) return null

    // Get the tail message first
    const tail = this.getTailMessageElement()
    if (!tail) return null

    // Only allow editing if the tail is owned by current user
    const tailParticipantId = parseInt(tail.dataset.messageParticipantId, 10)
    if (tailParticipantId !== this.currentMembershipIdValue) {
      // Tail is not owned by current user - cannot edit
      return null
    }

    return tail
  }

  /**
   * Find the last user-role message sent by current user, but ONLY if it's the tail.
   * This prevents attempting to edit non-tail messages which the server will reject.
   * @returns {HTMLElement|null}
   */
  findLastUserMessage() {
    const container = this.getMessagesContainer()
    if (!container) return null

    // Get the tail message first
    const tail = this.getTailMessageElement()
    if (!tail) return null

    // Only allow editing if the tail is a user message owned by current user
    const tailParticipantId = parseInt(tail.dataset.messageParticipantId, 10)
    if (tailParticipantId !== this.currentMembershipIdValue) {
      return null
    }
    if (tail.dataset.messageRole !== "user") {
      return null
    }

    return tail
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
  // Stop, Regenerate & Swipe Actions
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * Stop any running generation for this conversation.
   * Sends a request to cancel the running run and clear typing indicator.
   */
  async stopGeneration() {
    if (!this.hasStopUrlValue) return

    try {
      const { response } = await fetchTurboStream(this.stopUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.csrfToken,
          "Accept": "text/vnd.turbo-stream.html"
        }
      })

      if (!response.ok) {
        logger.error("Stop generation failed:", response.status)
      }
    } catch (error) {
      logger.error("Stop generation error:", error)
    }
  }

  /**
   * Regenerate the tail assistant message.
   * Does NOT send message_id; the server uses the tail by default.
   */
  async regenerateTailAssistant() {
    if (!this.hasRegenerateUrlValue) return

    try {
      const { response } = await fetchTurboStream(this.regenerateUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": this.csrfToken,
          "Accept": "text/vnd.turbo-stream.html"
        },
        body: "" // No message_id - server uses tail
      })

      if (!response.ok) {
        logger.error("Failed to regenerate:", response.status)
      }
    } catch (error) {
      logger.error("Regenerate error:", error)
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
      const { response } = await fetchTurboStream(swipeUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-Token": this.csrfToken,
          "Accept": "text/vnd.turbo-stream.html"
        },
        body: `dir=${direction}`
      })

      // 200 OK with empty body is valid (at boundary)
      // Non-2xx status is silently ignored (e.g., at swipe boundary)
      void response
    } catch (error) {
      logger.error("Swipe error:", error)
    }
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Hotkeys Help Modal
  // ─────────────────────────────────────────────────────────────────────────────

  /**
   * Show the hotkeys help modal.
   * Uses the global dialog element defined in _js_templates.html.erb.
   */
  showHotkeysHelpModal() {
    const modal = document.getElementById("hotkeys-help-modal")
    if (modal && modal.showModal) {
      modal.showModal()
    }
  }
}
