import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { CABLE_CONNECTED_EVENT, CABLE_DISCONNECTED_EVENT } from "../chat/events"
import { turboRequest } from "../request_helpers"

const CATCH_UP_MAX_PAGES = 5

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
    this.observeNewMessages()
    this.bindScrollEvents()
    this.setupIntersectionObserver()

    this.handleCableConnected = this.handleCableConnected.bind(this)
    this.handleCableDisconnected = this.handleCableDisconnected.bind(this)
    window.addEventListener(CABLE_CONNECTED_EVENT, this.handleCableConnected)
    window.addEventListener(CABLE_DISCONNECTED_EVENT, this.handleCableDisconnected)

    // Initial scroll to bottom after DOM is ready
    // Use setTimeout to ensure layout is complete after Turbo navigation
    setTimeout(() => this.scrollToBottomInstant(), 100)
  }

  disconnect() {
    this.disconnectObserver()
    this.unbindScrollEvents()
    this.disconnectIntersectionObserver()
    clearTimeout(this.scrollDebounceTimer)

    window.removeEventListener(CABLE_CONNECTED_EVENT, this.handleCableConnected)
    window.removeEventListener(CABLE_DISCONNECTED_EVENT, this.handleCableDisconnected)
  }

  /**
   * Check if user is currently at or near the bottom of the chat
   */
  isAtBottom() {
    if (!this.hasMessagesTarget) return true

    const { scrollTop, scrollHeight, clientHeight } = this.messagesTarget
    const distanceFromBottom = scrollHeight - scrollTop - clientHeight
    return distanceFromBottom <= this.thresholdValue
  }

  /**
   * Scroll to bottom instantly (no animation)
   */
  scrollToBottomInstant() {
    if (!this.hasMessagesTarget) return

    // Use scrollTop = scrollHeight which reliably scrolls to bottom
    // This works regardless of nested scrollable elements
    this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    this.autoScrollValue = true
    this.hideNewIndicator()
  }

  /**
   * Scroll to bottom with optional smooth animation
   */
  scrollToBottom(smooth = true) {
    if (!this.hasMessagesTarget) return

    if (smooth) {
      this.messagesTarget.scrollTo({
        top: this.messagesTarget.scrollHeight,
        behavior: "smooth"
      })
      this.autoScrollValue = true
      this.hideNewIndicator()
    } else {
      this.scrollToBottomInstant()
    }
  }

  scrollToMessage(messageId) {
    const message = this.messagesTarget.querySelector(`#${messageId}`)
    if (message) {
      message.scrollIntoView({ behavior: "smooth", block: "center" })
    }
  }

  // Actions

  jumpToBottom() {
    this.scrollToBottom(true)
  }

  // Private methods

  conversationId() {
    const id = Number(this.element.dataset.conversationChannelConversationValue)
    return Number.isFinite(id) && id > 0 ? id : null
  }

  shouldHandleCableEvent(event) {
    const myId = this.conversationId()
    const theirId = Number(event?.detail?.conversationId)

    if (!myId || !theirId) return true
    return myId === theirId
  }

  handleCableDisconnected(event) {
    if (!this.shouldHandleCableEvent(event)) return
    this.wasDisconnected = true
  }

  handleCableConnected(event) {
    if (!this.shouldHandleCableEvent(event)) return
    if (event?.detail?.reconnected !== true) return

    this.wasDisconnected = false
    this.syncNewMessages()
  }

  async syncNewMessages({ maxPages = CATCH_UP_MAX_PAGES } = {}) {
    if (this.syncingNewMessages) return
    if (!this.hasListTarget || !this.loadMoreUrlValue) return

    const lastMessage = this.getLastMessageElement()
    if (!lastMessage) return

    this.syncingNewMessages = true

    let cursorId = lastMessage.id.replace("message_", "")

    try {
      for (let page = 0; page < maxPages; page++) {
        const url = `${this.loadMoreUrlValue}?after=${encodeURIComponent(cursorId)}`

        const { response, renderedTurboStream, turboStreamHtml } = await turboRequest(url, {
          accept: "text/vnd.turbo-stream.html",
          headers: { "X-Requested-With": "XMLHttpRequest" }
        })

        if (response.status === 204) return
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`)
        }

        if (!renderedTurboStream || !turboStreamHtml?.trim()) return

        const newLastMessage = this.getLastMessageElement()
        if (!newLastMessage) return

        const nextCursorId = newLastMessage.id.replace("message_", "")
        if (nextCursorId === cursorId) return
        cursorId = nextCursorId
      }
    } catch (error) {
      logger.error("Failed to sync new messages:", error)
    } finally {
      this.syncingNewMessages = false
    }
  }

  observeNewMessages() {
    if (!this.hasListTarget) return

    this.mutationObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (mutation.type === "childList" && mutation.addedNodes.length > 0) {
          this.handleNewMessages(mutation.addedNodes)
        }
      }
    })

    this.mutationObserver.observe(this.listTarget, {
      childList: true,
      subtree: false
    })
  }

  disconnectObserver() {
    if (this.mutationObserver) {
      this.mutationObserver.disconnect()
      this.mutationObserver = null
    }
  }

  handleNewMessages(nodes) {
    if (this.loadingValue) return

    // Check if any of the added nodes are actual messages
    const hasNewMessage = Array.from(nodes).some(node =>
      node.nodeType === Node.ELEMENT_NODE
      && node.classList?.contains("mes")
      && typeof node.id === "string"
      && node.id.startsWith("message_")
    )

    if (!hasNewMessage) return

    this.hideEmptyState()

    // If user was at bottom, auto-scroll to show new message
    // Otherwise, show the "new messages" indicator
    if (this.autoScrollValue) {
      // Debounce scroll to handle rapid message insertions (user msg + AI response)
      // This ensures we scroll after ALL messages have been inserted
      clearTimeout(this.scrollDebounceTimer)
      this.scrollDebounceTimer = setTimeout(() => {
        this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
        this.autoScrollValue = true
      }, 100)
    } else {
      this.showNewIndicator()
    }
  }

  bindScrollEvents() {
    if (!this.hasMessagesTarget) return

    this.handleScroll = this.handleScroll.bind(this)
    this.messagesTarget.addEventListener("scroll", this.handleScroll, { passive: true })
  }

  unbindScrollEvents() {
    if (this.hasMessagesTarget) {
      this.messagesTarget.removeEventListener("scroll", this.handleScroll)
    }
  }

  handleScroll() {
    // Update auto-scroll state based on current scroll position
    this.autoScrollValue = this.isAtBottom()

    if (this.autoScrollValue) {
      this.hideNewIndicator()
    }
  }

  showNewIndicator() {
    if (this.hasNewIndicatorTarget) {
      this.newIndicatorTarget.classList.remove("hidden")
    }
  }

  hideNewIndicator() {
    if (this.hasNewIndicatorTarget) {
      this.newIndicatorTarget.classList.add("hidden")
    }
  }

  // Infinite scroll for loading older messages

  setupIntersectionObserver() {
    if (!this.hasLoadMoreTarget) return

    this.intersectionObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting && !this.loadingValue && this.hasMoreValue) {
            this.loadMoreMessages()
          }
        })
      },
      {
        root: this.hasMessagesTarget ? this.messagesTarget : null,
        rootMargin: "100px 0px 0px 0px",
        threshold: 0
      }
    )

    this.intersectionObserver.observe(this.loadMoreTarget)
  }

  disconnectIntersectionObserver() {
    if (this.intersectionObserver) {
      this.intersectionObserver.disconnect()
      this.intersectionObserver = null
    }
  }

  async loadMoreMessages() {
    if (this.loadingValue || !this.hasMoreValue || !this.loadMoreUrlValue) return

    this.loadingValue = true
    this.showLoadingIndicator()

    // Get the oldest message ID for cursor pagination
    const firstMessage = this.getFirstMessageElement()
    if (!firstMessage) {
      this.loadingValue = false
      this.hasMoreValue = false
      this.hideLoadingIndicator()
      return
    }

    const messageId = firstMessage.id.replace("message_", "")
    const url = `${this.loadMoreUrlValue}?before=${messageId}`

    // Store scroll position to restore after loading
    const scrollHeightBefore = this.messagesTarget.scrollHeight

    try {
      const { response, renderedTurboStream } = await turboRequest(url, {
        accept: "text/html",
        headers: { "X-Requested-With": "XMLHttpRequest" }
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      if (renderedTurboStream) return

      const html = await response.text()

      // Parse HTML and prepend messages
      const parser = new DOMParser()
      const doc = parser.parseFromString(html, "text/html")
      const newMessages = doc.querySelectorAll(".mes[id^='message_']")

      if (newMessages.length === 0) {
        this.hasMoreValue = false
        return
      }

      // Prepend messages in reverse order (oldest first at top)
      const fragment = document.createDocumentFragment()
      newMessages.forEach((msg) => fragment.appendChild(msg.cloneNode(true)))
      this.listTarget.insertBefore(fragment, this.listTarget.firstChild)

      // Restore scroll position
      const scrollHeightAfter = this.messagesTarget.scrollHeight
      const heightDiff = scrollHeightAfter - scrollHeightBefore
      this.messagesTarget.scrollTop += heightDiff

      // Check if we got fewer messages than expected (end of history)
      if (newMessages.length < 20) {
        this.hasMoreValue = false
      }
    } catch (error) {
      logger.error("Failed to load more messages:", error)
    } finally {
      this.loadingValue = false
      this.hideLoadingIndicator()
    }
  }

  getFirstMessageElement() {
    if (!this.hasListTarget) return null
    return this.listTarget.querySelector(".mes[id^='message_']")
  }

  getLastMessageElement() {
    if (!this.hasListTarget) return null

    let current = this.listTarget.lastElementChild
    while (current && !(current.id && current.id.startsWith("message_"))) {
      current = current.previousElementSibling
    }

    return current
  }

  showLoadingIndicator() {
    if (this.hasLoadMoreIndicatorTarget) {
      this.loadMoreIndicatorTarget.classList.remove("hidden")
    }
  }

  hideLoadingIndicator() {
    if (this.hasLoadMoreIndicatorTarget) {
      this.loadMoreIndicatorTarget.classList.add("hidden")
    }
  }

  hideEmptyState() {
    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.add("hidden")
    }
  }
}
