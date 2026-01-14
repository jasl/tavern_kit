import { Controller } from "@hotwired/stimulus"
import { dismiss } from "../ui/toast/animation"
import { connect, disconnect } from "../ui/toast/bindings"
import { clearTimers } from "../ui/toast/countdown"

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
    connect(this)
  }

  disconnect() {
    disconnect(this)
  }

  dismiss() {
    clearTimers(this)
    dismiss(this)
  }
}
