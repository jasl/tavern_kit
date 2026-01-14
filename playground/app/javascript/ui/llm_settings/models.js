export function populateModelDatalist(controller, models) {
  if (!controller.hasModelDatalistTarget) return

  const fragment = document.createDocumentFragment()

  for (const model of models || []) {
    if (model === undefined || model === null) continue

    const option = document.createElement("option")
    option.value = String(model)
    fragment.appendChild(option)
  }

  controller.modelDatalistTarget.replaceChildren(fragment)

  if (controller.hasModelInputTarget) {
    controller.modelInputTarget.focus()
  }
}
