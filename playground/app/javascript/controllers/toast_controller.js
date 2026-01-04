import { Controller } from "@hotwired/stimulus"

/**
 * Toast Controller
 * 
 * A global toast notification component that supports:
 * - Server-side rendering (content embedded in HTML)
 * - Auto-dismiss with countdown timer
 * - Manual dismiss via close button
 * - Multiple toast types (info, success, warning, error)
 * - Progress bar indicator for countdown
 * 
 * Usage:
 * <div data-controller="toast" 
 *      data-toast-duration-value="5000"
 *      data-toast-auto-dismiss-value="true">
 *   <div class="toast toast-top toast-end">
 *     <div class="alert alert-success" data-toast-target="alert">
 *       <span>登录成功！</span>
 *       <button type="button" data-action="toast#dismiss" class="btn btn-ghost btn-sm btn-circle">✕</button>
 *     </div>
 *   </div>
 * </div>
 */
export default class extends Controller {
  static targets = ["alert", "progress"]
  
  static values = {
    duration: { type: Number, default: 5000 },      // Duration in milliseconds
    autoDismiss: { type: Boolean, default: true },  // Whether to auto dismiss
    pauseOnHover: { type: Boolean, default: true }  // Pause countdown on hover
  }

  connect() {
    // Initialize state
    this.remainingTime = this.durationValue
    this.isPaused = false
    this.startTime = null
    this.animationFrameId = null

    // Store bound event handlers for proper cleanup
    this.boundPause = this.pause.bind(this)
    this.boundResume = this.resume.bind(this)
    this.hoverElement = null

    // Show the toast with animation
    this.show()

    // Setup auto dismiss if enabled
    if (this.autoDismissValue && this.durationValue > 0) {
      this.startCountdown()
      
      // Setup pause on hover if enabled
      if (this.pauseOnHoverValue) {
        // Use the visible element for hover events (the controller root can be 0×0 if it only contains a fixed toast)
        this.hoverElement = this.getAnimatedElement()
        this.hoverElement.addEventListener("mouseenter", this.boundPause)
        this.hoverElement.addEventListener("mouseleave", this.boundResume)
      }
    }
  }

  disconnect() {
    this.clearTimers()
    
    // Remove event listeners using stored bound references
    if (this.pauseOnHoverValue && this.hoverElement) {
      this.hoverElement.removeEventListener("mouseenter", this.boundPause)
      this.hoverElement.removeEventListener("mouseleave", this.boundResume)
      this.hoverElement = null
    }
  }

  show() {
    const el = this.getAnimatedElement()
    const enterTransform = this.getEnterTransform()

    // Add entrance animation
    el.style.transition = "none"
    el.style.willChange = "opacity, transform"
    el.style.opacity = "0"
    el.style.transform = enterTransform
    
    requestAnimationFrame(() => {
      el.style.transition = "opacity 300ms ease-out, transform 300ms ease-out"
      el.style.opacity = "1"
      el.style.transform = "translate3d(0, 0, 0)"
    })
  }

  dismiss() {
    this.clearTimers()

    const el = this.getAnimatedElement()
    const exitTransform = this.getEnterTransform()
    
    // Add exit animation
    el.style.transition = "opacity 200ms ease-in, transform 200ms ease-in"
    el.style.opacity = "0"
    el.style.transform = exitTransform

    // Remove element after animation (transitionend is more reliable than a fixed timeout)
    const remove = () => this.element.remove()
    el.addEventListener("transitionend", remove, { once: true })
    setTimeout(remove, 250)
  }

  startCountdown() {
    this.startTime = performance.now()
    this.updateProgress()
  }

  updateProgress() {
    if (this.isPaused) return

    const elapsed = performance.now() - this.startTime
    const remaining = this.remainingTime - elapsed

    if (remaining <= 0) {
      this.dismiss()
      return
    }

    // Update progress bar if exists
    if (this.hasProgressTarget) {
      const percentage = (remaining / this.durationValue) * 100
      this.progressTarget.style.width = `${percentage}%`
    }

    this.animationFrameId = requestAnimationFrame(() => this.updateProgress())
  }

  pause() {
    if (!this.autoDismissValue || this.isPaused) return
    
    this.isPaused = true
    const elapsed = performance.now() - this.startTime
    this.remainingTime = Math.max(0, this.remainingTime - elapsed)
    
    if (this.animationFrameId) {
      cancelAnimationFrame(this.animationFrameId)
      this.animationFrameId = null
    }
  }

  resume() {
    if (!this.autoDismissValue || !this.isPaused) return
    
    this.isPaused = false
    this.startTime = performance.now()
    this.updateProgress()
  }

  clearTimers() {
    if (this.animationFrameId) {
      cancelAnimationFrame(this.animationFrameId)
      this.animationFrameId = null
    }
  }

  /**
   * The element we animate and bind hover events to.
   * Animating the controller root can break `position: fixed` descendants (like daisyUI `.toast`).
   */
  getAnimatedElement() {
    return this.hasAlertTarget ? this.alertTarget : this.element
  }

  /**
   * Determine the entry/exit transform based on toast placement classes.
   */
  getEnterTransform() {
    const toast = this.element.querySelector(".toast")
    if (!toast) return "translateX(120%)"

    if (toast.classList.contains("toast-start")) return "translateX(-120%)"

    if (toast.classList.contains("toast-center")) {
      if (toast.classList.contains("toast-bottom")) return "translateY(120%)"
      return "translateY(-120%)"
    }

    // default: toast-end
    return "translateX(120%)"
  }
}
