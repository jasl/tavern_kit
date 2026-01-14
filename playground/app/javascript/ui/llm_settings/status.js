import { renderAlertBox } from "../alert_box"

export function displayConnectionResult(controller, result) {
  const statusContainer = document.getElementById(`connection_status_${controller.providerIdValue}`)
  if (!statusContainer) return

  if (result.success) {
    const responseText = (() => {
      if (!result.response) return null

      const raw = String(result.response)
      const trimmed = raw.substring(0, 100)
      const suffix = raw.length > 100 ? "..." : ""
      return `"${trimmed}${suffix}"`
    })()

    statusContainer.replaceChildren(renderAlertBox({
      variant: "success",
      icon: "check-circle",
      title: "Connection successful!",
      message: responseText,
      className: "py-3"
    }))
  } else {
    statusContainer.replaceChildren(renderAlertBox({
      variant: "error",
      icon: "alert-circle",
      title: "Connection failed",
      message: result.error ? String(result.error) : "Unknown error",
      className: "py-3"
    }))
  }
}

export function displayFetchError(controller, message) {
  const statusContainer = document.getElementById(`connection_status_${controller.providerIdValue}`)
  if (statusContainer) {
    statusContainer.replaceChildren(renderAlertBox({
      variant: "warning",
      icon: "alert-triangle",
      title: "Could not fetch models",
      message: message ? String(message) : "Unknown error",
      className: "py-3"
    }))
  }
}
