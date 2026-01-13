import { setInputValueFromResource } from "./inputs"
import { digValue } from "./nested"

export function applyServerResource(controller, resource) {
  if (!resource || typeof resource !== "object") return

  if (resource.settings && typeof resource.settings === "object") {
    syncSettingInputsFromSettings(controller, resource.settings)
  }

  const schemaRenderer = controller.application?.getControllerForElementAndIdentifier(controller.element, "schema-renderer")
  schemaRenderer?.applyVisibility?.()
}

export function syncSettingInputsFromSettings(controller, settings) {
  const inputs = Array.from(controller.element.querySelectorAll("[data-setting-path^='settings.']"))

  inputs.forEach((input) => {
    const type = input.dataset.settingType
    if (type === "array" || type === "json") return

    const fullPath = input.dataset.settingPath
    if (!fullPath) return

    const dotted = fullPath.replace(/^settings\./, "")
    const value = digValue(settings, dotted)
    if (value === undefined) return

    setInputValueFromResource(input, value)
  })
}
