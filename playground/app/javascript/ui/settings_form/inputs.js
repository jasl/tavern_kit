export function isSettingInput(element) {
  return element?.hasAttribute?.("data-setting-key") && element.hasAttribute("data-setting-path")
}

export function getInputValue(input, type) {
  if (input.type === "checkbox") {
    return input.checked
  }

  const rawValue = input.value

  switch (type) {
    case "number":
      return input.type === "range" ? parseFloat(rawValue) : (rawValue === "" ? null : parseFloat(rawValue))
    case "integer":
      return input.type === "range" ? parseInt(rawValue, 10) : (rawValue === "" ? null : parseInt(rawValue, 10))
    case "boolean":
      return rawValue === "true" || rawValue === "1"
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

export function setInputValueFromResource(input, value) {
  if (input.type === "checkbox") {
    input.checked = value === true
    return
  }

  if (value === null || value === undefined) {
    input.value = ""
    return
  }

  input.value = String(value)
}
