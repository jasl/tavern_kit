import { Controller } from "@hotwired/stimulus"

/**
 * Dropzone Controller
 *
 * Handles drag-and-drop file uploads with visual feedback.
 */
export default class extends Controller {
  static targets = ["zone", "input"]

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
      this.submitForm()
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
      this.submitForm()
    }
  }

  submitForm() {
    // Disable Turbo for this form submission to ensure full page refresh
    // This is needed because requestSubmit() may not respect data-turbo="false"
    this.element.setAttribute("data-turbo", "false")
    this.element.requestSubmit()
  }
}
