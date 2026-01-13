import { escapeHtml } from "../../dom_helpers"

export function populateModelDatalist(controller, models) {
  if (!controller.hasModelDatalistTarget) return

  controller.modelDatalistTarget.innerHTML = models
    .map(model => `<option value="${escapeHtml(model)}">`)
    .join("")

  if (controller.hasModelInputTarget) {
    controller.modelInputTarget.focus()
  }
}
