function formatFileSize(bytes) {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function normalizeFiles(files) {
  if (!files) return []
  // FileList is iterable but not a real array in all environments
  return Array.from(files)
}

function filesSummary(files) {
  const list = normalizeFiles(files)
  const totalBytes = list.reduce((sum, f) => sum + (f?.size || 0), 0)
  return {
    count: list.length,
    totalBytes,
    totalSizeLabel: formatFileSize(totalBytes),
    list,
  }
}

function setLorebookNameInputState(controller, count) {
  if (!controller.hasNameInputTarget) return

  const input = controller.nameInputTarget

  // Preserve original placeholder so we can restore it.
  input.dataset.originalPlaceholder ||= input.getAttribute("placeholder") || ""

  if (count > 1) {
    input.value = ""
    input.disabled = true
    input.setAttribute("placeholder", "Disabled for multiple files (name is derived per file)")
  } else {
    input.disabled = false
    input.setAttribute("placeholder", input.dataset.originalPlaceholder)
  }
}

export function showFilesInfo(controller, files) {
  const summary = filesSummary(files)
  if (summary.count === 0) return

  const first = summary.list[0]

  if (controller.hasFileNameTarget) {
    if (summary.count === 1) {
      controller.fileNameTarget.textContent = first.name
    } else {
      const preview = summary.list
        .slice(0, 3)
        .map((f) => f.name)
        .join(", ")
      const suffix = summary.count > 3 ? `, +${summary.count - 3} more` : ""
      controller.fileNameTarget.textContent = `${summary.count} files selected: ${preview}${suffix}`
    }
  }
  if (controller.hasFileSizeTarget) {
    if (summary.count === 1) {
      controller.fileSizeTarget.textContent = formatFileSize(first.size)
    } else {
      controller.fileSizeTarget.textContent = `Total: ${summary.totalSizeLabel}`
    }
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

  setLorebookNameInputState(controller, summary.count)
}

// Backwards-compatible wrapper (older callers passed a single File)
export function showFileInfo(controller, file) {
  showFilesInfo(controller, [file])
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

  // Restore Name input for lorebook import (if present).
  if (controller.hasNameInputTarget) {
    controller.nameInputTarget.disabled = false
    controller.nameInputTarget.setAttribute(
      "placeholder",
      controller.nameInputTarget.dataset.originalPlaceholder || controller.nameInputTarget.getAttribute("placeholder") || ""
    )
  }
}
