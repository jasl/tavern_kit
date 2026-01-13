import { layoutFromDataAttributes } from "./layout"
import { getTabTarget } from "./targets"

export function scheduleVisibilityUpdate(controller) {
  if (controller.visibilityRaf) return

  controller.visibilityRaf = requestAnimationFrame(() => {
    controller.visibilityRaf = null
    applyVisibility(controller)
  })
}

export function applyVisibility(controller) {
  const context = controller.contextValue || {}
  const items = controller.layout || layoutFromDataAttributes(controller.fields)

  items.forEach((item) => {
    const rule = item.visibleWhen

    if (!rule) {
      showField(item.element)
      return
    }

    let shouldShow = true

    if (rule?.context && Object.prototype.hasOwnProperty.call(rule, "const")) {
      const ctxVal = context[rule.context]
      shouldShow = ctxVal === rule.const
    }

    if (shouldShow && rule?.ref) {
      const refValue = readValueForRef(controller, rule.ref)
      if (Array.isArray(rule.in)) {
        shouldShow = rule.in.includes(refValue)
      } else if (Object.prototype.hasOwnProperty.call(rule, "const")) {
        shouldShow = refValue === rule.const
      }
    }

    if (shouldShow) {
      showField(item.element)
    } else {
      hideField(item.element)
    }
  })

  hideEmptyGroups(controller)
}

function showField(field) {
  field.classList.remove("hidden")
  field.removeAttribute("aria-hidden")

  field.querySelectorAll("input, select, textarea").forEach((el) => {
    if (el.dataset.schemaDisabled === "true") return
    if (el.dataset.visibilityDisabled === "true") {
      el.removeAttribute("disabled")
      delete el.dataset.visibilityDisabled
    }
  })
}

function hideField(field) {
  field.classList.add("hidden")
  field.setAttribute("aria-hidden", "true")

  field.querySelectorAll("input, select, textarea").forEach((el) => {
    if (el.dataset.schemaDisabled === "true") return
    if (el.disabled) return

    el.setAttribute("disabled", "disabled")
    el.dataset.visibilityDisabled = "true"
  })
}

function hideEmptyGroups(controller) {
  controller.constructor.TABS.forEach((tabName) => {
    const container = getTabTarget(controller, tabName)
    if (!container) return

    container.querySelectorAll("[data-schema-group='true']").forEach((group) => {
      const visible = group.querySelectorAll("[data-schema-field='true']:not(.hidden)")
      group.classList.toggle("hidden", visible.length === 0)
    })
  })
}

function readValueForRef(controller, ref) {
  const settingPath = resolveRefSettingPath(controller, ref)
  if (!settingPath) return undefined

  const input = controller.element.querySelector(`[data-setting-path='${settingPath}'][data-setting-key]`)
  if (!input) return undefined

  return readInputValue(input)
}

function resolveRefSettingPath(controller, ref) {
  if (typeof ref !== "string" || ref.length === 0) return null

  if (ref.startsWith("settings.") || ref.startsWith("data.")) return ref

  const direct = controller.element.querySelector(`[data-setting-path='${ref}'][data-setting-key]`)
  if (direct) return ref

  const settings = controller.element.querySelector(`[data-setting-path='settings.${ref}'][data-setting-key]`)
  if (settings) return `settings.${ref}`

  const data = controller.element.querySelector(`[data-setting-path='data.${ref}'][data-setting-key]`)
  if (data) return `data.${ref}`

  return null
}

function readInputValue(input) {
  if (input.type === "checkbox") {
    return input.checked
  }

  const rawValue = input.value
  const type = input.dataset.settingType

  switch (type) {
    case "integer":
      return rawValue === "" ? null : parseInt(rawValue, 10)
    case "number":
      return rawValue === "" ? null : parseFloat(rawValue)
    case "array":
    case "json":
      try {
        return JSON.parse(rawValue)
      } catch {
        return rawValue
      }
    default:
      return rawValue
  }
}
