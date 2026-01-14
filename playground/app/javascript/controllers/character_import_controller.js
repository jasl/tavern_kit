import { Controller } from "@hotwired/stimulus"
import { connectImportDropzone, disconnectImportDropzone } from "../ui/import_dropzone/bindings"
import { dragenter, dragleave, dragover, drop } from "../ui/import_dropzone/drag_events"
import { clearFile, click, fileSelected } from "../ui/import_dropzone/file_events"
import { resetState, submitStart } from "../ui/import_dropzone/state"

/**
 * Character Import Controller
 *
 * Enhanced dropzone with file preview and submit control.
 * Shows upload progress and handles async import flow.
 */
export default class extends Controller {
  static targets = ["zone", "input", "idle", "uploading", "fileInfo", "fileName", "fileSize", "submitBtn"]

  connect() {
    connectImportDropzone(this)
  }

  disconnect() {
    disconnectImportDropzone(this)
  }

  /**
   * Reset the import form to initial state
   */
  resetState() {
    resetState(this)
  }

  dragover(event) {
    dragover(event)
  }

  dragenter(event) {
    dragenter(this, event)
  }

  dragleave(event) {
    dragleave(this, event)
  }

  drop(event) {
    drop(this, event)
  }

  click(event) {
    click(this, event)
  }

  fileSelected() {
    fileSelected(this)
  }

  clearFile(event) {
    clearFile(this, event)
  }

  // Called when form is submitted
  submitStart() {
    submitStart(this)
  }
}
