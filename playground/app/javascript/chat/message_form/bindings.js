import { CABLE_CONNECTED_EVENT, CABLE_DISCONNECTED_EVENT, SCHEDULING_STATE_CHANGED_EVENT } from "../events"
import { handleCableConnected, handleCableDisconnected, handleSchedulingStateChanged, syncCableConnectedFromGlobalState } from "./cable_events"
import { updateLockedState } from "./lock_state"
import { handleSubmitEnd } from "./submit"

export function bindMessageFormEvents(controller) {
  const onSubmitEnd = (event) => handleSubmitEnd(controller, event)
  const onSchedulingStateChanged = (event) => handleSchedulingStateChanged(controller, event)
  const onCableConnected = (event) => handleCableConnected(controller, event)
  const onCableDisconnected = (event) => handleCableDisconnected(controller, event)

  controller.element.addEventListener("turbo:submit-end", onSubmitEnd)
  window.addEventListener(SCHEDULING_STATE_CHANGED_EVENT, onSchedulingStateChanged)
  window.addEventListener(CABLE_CONNECTED_EVENT, onCableConnected)
  window.addEventListener(CABLE_DISCONNECTED_EVENT, onCableDisconnected)

  syncCableConnectedFromGlobalState(controller)
  updateLockedState(controller)

  return () => {
    controller.element.removeEventListener("turbo:submit-end", onSubmitEnd)
    window.removeEventListener(SCHEDULING_STATE_CHANGED_EVENT, onSchedulingStateChanged)
    window.removeEventListener(CABLE_CONNECTED_EVENT, onCableConnected)
    window.removeEventListener(CABLE_DISCONNECTED_EVENT, onCableDisconnected)
  }
}
