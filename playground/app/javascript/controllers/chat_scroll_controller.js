import { Controller } from "@hotwired/stimulus"

/**
 * Chat Scroll Controller
 *
 * Manages chat message list scrolling behavior:
 * - Auto-scroll to bottom on new messages
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
    this.scrollToBottom(false)
    this.setupIntersectionObserver()
  }

  disconnect() {
    this.disconnectObserver()
    this.unbindScrollEvents()
    this.disconnectIntersectionObserver()
  }

  scrollToBottom(smooth = true) {
    if (!this.hasMessagesTarget) return

    const behavior = smooth ? "smooth" : "auto"
    this.messagesTarget.scrollTo({
      top: this.messagesTarget.scrollHeight,
      behavior
    })
    this.autoScrollValue = true
    this.hideNewIndicator()
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
      && node.classList?.contains("chat")
      && typeof node.id === "string"
      && node.id.startsWith("message_")
    )

    if (!hasNewMessage) return

    this.hideEmptyState()

    if (this.autoScrollValue) {
      // User is at bottom, auto-scroll
      this.scrollToBottom(true)
    } else {
      // User has scrolled up, show indicator
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
    const { scrollTop, scrollHeight, clientHeight } = this.messagesTarget
    const distanceFromBottom = scrollHeight - scrollTop - clientHeight

    // Update auto-scroll state based on scroll position
    this.autoScrollValue = distanceFromBottom <= this.thresholdValue

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
      const response = await fetch(url, {
        headers: {
          Accept: "text/html",
          "X-Requested-With": "XMLHttpRequest"
        }
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const html = await response.text()

      // Check if Turbo Stream response
      if (response.headers.get("Content-Type")?.includes("turbo-stream")) {
        Turbo.renderStreamMessage(html)
      } else {
        // Parse HTML and prepend messages
        const parser = new DOMParser()
        const doc = parser.parseFromString(html, "text/html")
        const newMessages = doc.querySelectorAll(".chat[id^='message_']")

        if (newMessages.length === 0) {
          this.hasMoreValue = false
        } else {
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
        }
      }
    } catch (error) {
      console.error("Failed to load more messages:", error)
    } finally {
      this.loadingValue = false
      this.hideLoadingIndicator()
    }
  }

  getFirstMessageElement() {
    if (!this.hasListTarget) return null
    return this.listTarget.querySelector(".chat[id^='message_']")
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
