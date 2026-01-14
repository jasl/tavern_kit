import { clearSelectedFile, showFileInfo } from "./file_info"

export function click(controller, event) {
  if (!controller.hasInputTarget) return

  if (event.target !== controller.inputTarget) {
    event.preventDefault()
    event.stopPropagation()
    controller.inputTarget.click()
  }
}

export function fileSelected(controller) {
  if (!controller.hasInputTarget) return

  const files = controller.inputTarget.files
  if (files && files.length > 0) {
    showFileInfo(controller, files[0])
  }
}

export function clearFile(controller, event) {
  event.preventDefault()
  event.stopPropagation()
  clearSelectedFile(controller)
}

