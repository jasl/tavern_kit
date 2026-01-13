import { Controller } from "@hotwired/stimulus"
import logger from "../logger"
import { fetchTurboStream } from "../turbo_fetch"

/**
 * Touch Swipe Controller
 *
 * Handles horizontal swipe gestures on mobile devices for navigating
 * between message swipe versions.
 *
 * Only triggers on elements that have swipeable content (assistant messages
 * with multiple swipes).
 *
 * Detection parameters:
 * - Minimum horizontal distance: 50px
 * - Maximum vertical distance: 100px (prevents triggering during scroll)
 * - Gesture must be more horizontal than vertical (angle check)
 *
 * @example HTML structure
 *   <div data-controller="touch-swipe"
 *        data-touch-swipe-conversation-value="123"
 *        data-touch-swipe-message-value="456"
 *        data-touch-swipe-has-swipes-value="true">
 *     ...message content...
 *   </div>
 */
export default class extends Controller {
  static values = {
    conversation: Number,
    message: Number,
    hasSwipes: { type: Boolean, default: false }
  }

  // Touch state
  touchStartX = 0
  touchStartY = 0
  touchStartTime = 0
  isSwiping = false

  // Configuration
  minSwipeDistance = 50    // Minimum horizontal distance to trigger swipe
  maxVerticalDistance = 100  // Maximum vertical distance (prevents scroll conflicts)
  maxSwipeTime = 500       // Maximum time (ms) for a valid swipe gesture

  connect() {
    // Only enable touch handling if this message has swipes
    if (!this.hasSwipesValue) return

    this.handleTouchStart = this.handleTouchStart.bind(this)
    this.handleTouchMove = this.handleTouchMove.bind(this)
    this.handleTouchEnd = this.handleTouchEnd.bind(this)

    this.element.addEventListener("touchstart", this.handleTouchStart, { passive: true })
    this.element.addEventListener("touchmove", this.handleTouchMove, { passive: true })
    this.element.addEventListener("touchend", this.handleTouchEnd, { passive: true })
  }

  disconnect() {
    this.element.removeEventListener("touchstart", this.handleTouchStart)
    this.element.removeEventListener("touchmove", this.handleTouchMove)
    this.element.removeEventListener("touchend", this.handleTouchEnd)
  }

  handleTouchStart(event) {
    // Only handle single-touch gestures
    if (event.touches.length !== 1) return

    const touch = event.touches[0]
    this.touchStartX = touch.clientX
    this.touchStartY = touch.clientY
    this.touchStartTime = Date.now()
    this.isSwiping = false
  }

  handleTouchMove(event) {
    // Check if we're in a potential swipe
    if (event.touches.length !== 1) return

    const touch = event.touches[0]
    const deltaX = touch.clientX - this.touchStartX
    const deltaY = touch.clientY - this.touchStartY

    // If primarily horizontal movement and beyond threshold, mark as swiping
    // This helps provide visual feedback or prevent other interactions
    if (Math.abs(deltaX) > 20 && Math.abs(deltaX) > Math.abs(deltaY) * 1.5) {
      this.isSwiping = true
    }
  }

  handleTouchEnd(event) {
    // Calculate final swipe metrics
    const touch = event.changedTouches[0]
    const deltaX = touch.clientX - this.touchStartX
    const deltaY = touch.clientY - this.touchStartY
    const deltaTime = Date.now() - this.touchStartTime

    // Reset state
    const _wasSwipeIntent = this.isSwiping
    this.isSwiping = false

    // Validate swipe gesture
    if (!this.isValidSwipe(deltaX, deltaY, deltaTime)) return

    // Determine direction and trigger swipe
    const direction = deltaX > 0 ? "left" : "right"
    this.triggerSwipe(direction)
  }

  /**
   * Validate if the touch gesture qualifies as a horizontal swipe.
   * @param {number} deltaX - Horizontal distance
   * @param {number} deltaY - Vertical distance
   * @param {number} deltaTime - Time elapsed (ms)
   * @returns {boolean}
   */
  isValidSwipe(deltaX, deltaY, deltaTime) {
    // Must exceed minimum horizontal distance
    if (Math.abs(deltaX) < this.minSwipeDistance) return false

    // Must not exceed maximum vertical distance
    if (Math.abs(deltaY) > this.maxVerticalDistance) return false

    // Must be within time limit
    if (deltaTime > this.maxSwipeTime) return false

    // Must be more horizontal than vertical (prevent triggering on scroll)
    if (Math.abs(deltaY) >= Math.abs(deltaX)) return false

    return true
  }

  /**
   * Trigger a swipe action.
   * @param {string} direction - "left" or "right"
   */
  async triggerSwipe(direction) {
    if (!this.hasConversationValue || !this.hasMessageValue) return

    const swipeUrl = `/conversations/${this.conversationValue}/messages/${this.messageValue}/swipe`

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
      logger.error("Touch swipe error:", error)
    }
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
