export const CABLE_CONNECTED_EVENT = "cable:connected"
export const CABLE_DISCONNECTED_EVENT = "cable:disconnected"
export const SCHEDULING_STATE_CHANGED_EVENT = "scheduling:state-changed"
export const USER_TYPING_DISABLE_AUTO_EVENT = "user:typing:disable-auto"
export const USER_TYPING_DISABLE_AUTO_WITHOUT_HUMAN_EVENT = "user:typing:disable-auto-without-human"
export const AUTO_WITHOUT_HUMAN_DISABLED_EVENT = "auto-without-human:disabled"

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
