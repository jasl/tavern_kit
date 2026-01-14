import { resetState } from "./state"

export function connectImportDropzone(controller) {
  controller.dragCounter = 0
  resetState(controller)

  controller.dialog = controller.element.closest("dialog")
  if (!controller.dialog) return

  controller.handleDialogClose = () => resetState(controller)
  controller.dialog.addEventListener("close", controller.handleDialogClose)
}

export function disconnectImportDropzone(controller) {
  if (controller.dialog && controller.handleDialogClose) {
    controller.dialog.removeEventListener("close", controller.handleDialogClose)
  }

  controller.dialog = null
  controller.handleDialogClose = null
}

