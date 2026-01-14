import { showFileInfo } from "./file_info"

function highlightZone(controller, highlight) {
  if (!controller.hasZoneTarget) return

  controller.zoneTarget.classList.toggle("border-primary", highlight)
  controller.zoneTarget.classList.toggle("bg-primary/10", highlight)
}

export function dragover(event) {
  event.preventDefault()
}

export function dragenter(controller, event) {
  event.preventDefault()

  controller.dragCounter = (controller.dragCounter || 0) + 1
  highlightZone(controller, true)
}

export function dragleave(controller, event) {
  event.preventDefault()

  controller.dragCounter = Math.max(0, (controller.dragCounter || 0) - 1)

  if (controller.dragCounter === 0) {
    highlightZone(controller, false)
  }
}

export function drop(controller, event) {
  event.preventDefault()

  controller.dragCounter = 0
  highlightZone(controller, false)

  const files = event.dataTransfer?.files
  if (!files || files.length === 0) return

  if (controller.hasInputTarget) {
    controller.inputTarget.files = files
  }

  showFileInfo(controller, files[0])
}

