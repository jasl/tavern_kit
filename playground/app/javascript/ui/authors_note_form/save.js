import { updateCharCount } from "./char_count"
import { collectFormData } from "./form_data"
import { sendUpdate } from "./requests"

export function connect(controller) {
  controller.debounceTimer = null
  updateCharCount(controller)
}

export function disconnect(controller) {
  if (controller.debounceTimer) {
    clearTimeout(controller.debounceTimer)
  }
}

export function debounceSave(controller) {
  updateCharCount(controller)

  if (controller.debounceTimer) {
    clearTimeout(controller.debounceTimer)
  }

  controller.debounceTimer = setTimeout(() => {
    save(controller)
  }, controller.debounceValue)
}

export function save(controller) {
  const data = collectFormData(controller)
  sendUpdate(controller, data)
}

