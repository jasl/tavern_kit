import { Controller } from "@hotwired/stimulus"

/**
 * Lorebook Import Controller
 *
 * Enhanced dropzone with file preview and submit control.
 * Shows upload progress and handles async import flow.
 */
export default class extends Controller {
  static targets = ["zone", "input", "idle", "uploading", "fileInfo", "fileName", "fileSize", "submitBtn", "nameInput"]

  connect() {
    this.dragCounter = 0
    // Reset state on connect
    this.resetState()

    // Listen to dialog close event to reset state for next open
    this.dialog = this.element.closest("dialog")
    if (this.dialog) {
      this.handleDialogClose = this.resetState.bind(this)
      this.dialog.addEventListener("close", this.handleDialogClose)
    }
  }

  disconnect() {
    if (this.dialog && this.handleDialogClose) {
      this.dialog.removeEventListener("close", this.handleDialogClose)
    }
  }

  /**
   * Reset the import form to initial state
   */
  resetState() {
    // Clear file input
    if (this.hasInputTarget) {
      this.inputTarget.value = ""
    }

    // Clear name input
    if (this.hasNameInputTarget) {
      this.nameInputTarget.value = ""
    }

    // Hide file info, show dropzone
    if (this.hasFileInfoTarget) {
      this.fileInfoTarget.classList.add("hidden")
    }
    if (this.hasZoneTarget) {
      this.zoneTarget.classList.remove("hidden")
    }

    // Reset idle/uploading states
    if (this.hasIdleTarget) {
      this.idleTarget.classList.remove("hidden")
    }
    if (this.hasUploadingTarget) {
      this.uploadingTarget.classList.add("hidden")
    }

    // Disable submit button
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = true
    }
  }

  dragover(event) {
    event.preventDefault()
  }

  dragenter(event) {
    event.preventDefault()
    this.dragCounter++
    this.zoneTarget.classList.add("border-primary", "bg-primary/10")
  }

  dragleave(event) {
    event.preventDefault()
    this.dragCounter--
    if (this.dragCounter === 0) {
      this.zoneTarget.classList.remove("border-primary", "bg-primary/10")
    }
  }

  drop(event) {
    event.preventDefault()
    this.dragCounter = 0
    this.zoneTarget.classList.remove("border-primary", "bg-primary/10")

    const files = event.dataTransfer.files
    if (files.length > 0) {
      this.inputTarget.files = files
      this.showFileInfo(files[0])
    }
  }

  click(event) {
    // Don't trigger if clicking on the input itself
    if (event.target !== this.inputTarget) {
      event.preventDefault()
      event.stopPropagation()
      this.inputTarget.click()
    }
  }

  fileSelected() {
    if (this.inputTarget.files.length > 0) {
      this.showFileInfo(this.inputTarget.files[0])
    }
  }

  showFileInfo(file) {
    if (this.hasFileNameTarget) {
      this.fileNameTarget.textContent = file.name
    }
    if (this.hasFileSizeTarget) {
      this.fileSizeTarget.textContent = this.formatFileSize(file.size)
    }
    if (this.hasFileInfoTarget) {
      this.fileInfoTarget.classList.remove("hidden")
    }
    // Hide the entire dropzone when file is selected
    if (this.hasZoneTarget) {
      this.zoneTarget.classList.add("hidden")
    }
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = false
    }
  }

  clearFile(event) {
    event.preventDefault()
    event.stopPropagation()

    this.inputTarget.value = ""
    if (this.hasFileInfoTarget) {
      this.fileInfoTarget.classList.add("hidden")
    }
    // Show dropzone again when file is cleared
    if (this.hasZoneTarget) {
      this.zoneTarget.classList.remove("hidden")
    }
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = true
    }
  }

  formatFileSize(bytes) {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  // Called when form is submitted
  submitStart() {
    // Hide file info and show uploading state in the zone
    if (this.hasFileInfoTarget) {
      this.fileInfoTarget.classList.add("hidden")
    }
    if (this.hasZoneTarget) {
      this.zoneTarget.classList.remove("hidden")
    }
    if (this.hasIdleTarget) {
      this.idleTarget.classList.add("hidden")
    }
    if (this.hasUploadingTarget) {
      this.uploadingTarget.classList.remove("hidden")
    }
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = true
    }
  }
}
