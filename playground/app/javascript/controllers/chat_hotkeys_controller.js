import { Controller } from "@hotwired/stimulus"
import { handleKeydown as handleChatHotkeysKeydown } from "../chat/hotkeys/keydown"
import { stopGeneration } from "../chat/hotkeys/actions"

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
    handleChatHotkeysKeydown(this, event)
  }

  async stop(event) {
    event?.preventDefault()
    await stopGeneration(this)
  }
}
