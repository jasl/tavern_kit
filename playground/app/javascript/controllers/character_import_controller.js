import { Controller } from "@hotwired/stimulus"

/**
 * Character Import Controller
 *
 * Enhanced dropzone with file preview and submit control.
 * Shows upload progress and handles async import flow.
 */
export default class extends Controller {
  static targets = ["zone", "input", "idle", "uploading", "fileInfo", "fileName", "fileSize", "submitBtn"]

  connect() {
    this.dragCounter = 0
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
    if (this.hasIdleTarget) {
      this.idleTarget.classList.add("hidden")
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
    if (this.hasIdleTarget) {
      this.idleTarget.classList.remove("hidden")
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
