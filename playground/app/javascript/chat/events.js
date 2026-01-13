export const CABLE_CONNECTED_EVENT = "cable:connected"
export const CABLE_DISCONNECTED_EVENT = "cable:disconnected"
export const SCHEDULING_STATE_CHANGED_EVENT = "scheduling:state-changed"
export const USER_TYPING_DISABLE_COPILOT_EVENT = "user:typing:disable-copilot"
export const USER_TYPING_DISABLE_AUTO_MODE_EVENT = "user:typing:disable-auto-mode"
export const AUTO_MODE_DISABLED_EVENT = "auto-mode:disabled"

export function dispatchWindowEvent(name, detail = null, options = {}) {
  const {
    bubbles = true,
    cancelable = false
  } = options || {}

  window.dispatchEvent(new CustomEvent(name, {
    detail: detail || {},
    bubbles,
    cancelable
  }))
}

