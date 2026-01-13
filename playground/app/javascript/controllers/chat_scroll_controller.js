import { Controller } from "@hotwired/stimulus"
import { isAtBottom, scrollToBottom, scrollToBottomInstant, scrollToMessage } from "../chat/scroll/bottom"
import { observeNewMessages } from "../chat/scroll/new_messages_observer"
import { bindScrollEvents } from "../chat/scroll/scroll_events"
import { setupIntersectionObserver } from "../chat/scroll/history_loader"
import { bindCableSync } from "../chat/scroll/cable_sync"

/**
 * Chat Scroll Controller
 *
 * Manages chat message list scrolling behavior:
 * - Auto-scroll to bottom on new messages (only if user is at bottom)
 * - Infinite scroll to load older messages when scrolling to top
 * - Preserve position when loading history
 * - Show "new messages" indicator when scrolled up
 */
export default class extends Controller {
  static targets = ["messages", "list", "newIndicator", "loadMore", "loadMoreIndicator", "emptyState"]
  static values = {
    autoScroll: { type: Boolean, default: true },
    threshold: { type: Number, default: 100 },
    loadMoreUrl: { type: String, default: "" },
    loading: { type: Boolean, default: false },
    hasMore: { type: Boolean, default: true }
  }

  connect() {
    this.disconnectNewMessagesObserver = observeNewMessages(this)
    this.disconnectScrollEvents = bindScrollEvents(this)
    this.disconnectIntersectionObserver = setupIntersectionObserver(this)
    this.disconnectCableSync = bindCableSync(this)

    // Initial scroll to bottom after DOM is ready
    // Use setTimeout to ensure layout is complete after Turbo navigation
    setTimeout(() => this.scrollToBottomInstant(), 100)
  }

  disconnect() {
    this.disconnectNewMessagesObserver?.()
    this.disconnectScrollEvents?.()
    this.disconnectIntersectionObserver?.()
    clearTimeout(this.scrollDebounceTimer)
    this.disconnectCableSync?.()
  }

  /**
   * Check if user is currently at or near the bottom of the chat
   */
  isAtBottom() {
    return isAtBottom(this)
  }

  /**
   * Scroll to bottom instantly (no animation)
   */
  scrollToBottomInstant() {
    scrollToBottomInstant(this)
  }

  /**
   * Scroll to bottom with optional smooth animation
   */
  scrollToBottom(smooth = true) {
    scrollToBottom(this, { smooth })
  }

  scrollToMessage(messageId) {
    scrollToMessage(this, messageId)
  }

  // Actions

  jumpToBottom() {
    this.scrollToBottom(true)
  }
}
