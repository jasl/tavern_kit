import { Controller } from "@hotwired/stimulus"

/**
 * Entry Form Controller
 *
 * Handles dynamic field visibility based on entry settings.
 */
export default class extends Controller {
  static targets = ["selectiveFields", "depthField", "roleField", "outletField"]

  connect() {
    this.updateFieldVisibility()
  }

  toggleSelective(event) {
    if (this.hasSelectiveFieldsTarget) {
      this.selectiveFieldsTarget.classList.toggle("hidden", !event.target.checked)
    }
  }

  togglePositionFields(event) {
    const position = event.target.value

    // Show depth/role fields for "at_depth" position
    const showDepth = position === "at_depth"
    if (this.hasDepthFieldTarget) {
      this.depthFieldTarget.classList.toggle("hidden", !showDepth)
    }
    if (this.hasRoleFieldTarget) {
      this.roleFieldTarget.classList.toggle("hidden", !showDepth)
    }

    // Show outlet field for "outlet" position
    const showOutlet = position === "outlet"
    if (this.hasOutletFieldTarget) {
      this.outletFieldTarget.classList.toggle("hidden", !showOutlet)
    }
  }

  updateFieldVisibility() {
    // Check initial position
    const positionSelect = this.element.querySelector('select[name*="position"]')
    if (positionSelect) {
      this.togglePositionFields({ target: positionSelect })
    }

    // Check initial selective state
    const selectiveCheckbox = this.element.querySelector('input[name*="selective"]')
    if (selectiveCheckbox && this.hasSelectiveFieldsTarget) {
      this.selectiveFieldsTarget.classList.toggle("hidden", !selectiveCheckbox.checked)
    }
  }
}
