import { syncCheckboxes, updateCounter, updateHiddenInputs } from "./ui_sync"

export function connect(controller) {
  controller.boundHandleFrameLoad = controller.handleFrameLoad.bind(controller)
  controller.element.addEventListener("turbo:frame-load", controller.boundHandleFrameLoad)

  syncCheckboxes(controller)
  updateCounter(controller)
  updateHiddenInputs(controller)
}

export function disconnect(controller) {
  controller.element.removeEventListener("turbo:frame-load", controller.boundHandleFrameLoad)
}

