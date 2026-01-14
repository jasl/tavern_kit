function formatFileSize(bytes) {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

export function showFileInfo(controller, file) {
  if (controller.hasFileNameTarget) {
    controller.fileNameTarget.textContent = file.name
  }
  if (controller.hasFileSizeTarget) {
    controller.fileSizeTarget.textContent = formatFileSize(file.size)
  }

  if (controller.hasFileInfoTarget) {
    controller.fileInfoTarget.classList.remove("hidden")
  }

  if (controller.hasZoneTarget) {
    controller.zoneTarget.classList.add("hidden")
  }

  if (controller.hasSubmitBtnTarget) {
    controller.submitBtnTarget.disabled = false
  }
}

export function clearSelectedFile(controller) {
  if (controller.hasInputTarget) {
    controller.inputTarget.value = ""
  }

  if (controller.hasFileInfoTarget) {
    controller.fileInfoTarget.classList.add("hidden")
  }

  if (controller.hasZoneTarget) {
    controller.zoneTarget.classList.remove("hidden")
  }

  if (controller.hasSubmitBtnTarget) {
    controller.submitBtnTarget.disabled = true
  }
}
