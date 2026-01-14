import { Controller } from "@hotwired/stimulus"
import { connect, disconnect } from "../chat/touch_swipe/bindings"
import { handleTouchEnd, handleTouchMove, handleTouchStart } from "../chat/touch_swipe/gesture"
import { triggerSwipe } from "../chat/touch_swipe/requests"

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
    connect(this)
  }

  disconnect() {
    disconnect(this)
  }

  handleTouchStart(event) {
    handleTouchStart(this, event)
  }

  handleTouchMove(event) {
    handleTouchMove(this, event)
  }

  handleTouchEnd(event) {
    const direction = handleTouchEnd(this, event)
    if (!direction) return
    triggerSwipe(this, direction)
  }
}
