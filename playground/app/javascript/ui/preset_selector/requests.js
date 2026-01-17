import logger from "../../logger"
import { showToast, turboRequest } from "../../request_helpers"

function dispatchSaveIndicator(status, message = null) {
  const detail = {
    status,
    message,
    at: Date.now(),
    source: "preset-selector"
  }

  // Persist last status so a newly-replaced sidebar can "replay" it on connect.
  window.__saveIndicatorLast = detail

  window.dispatchEvent(new CustomEvent("save-indicator:status", { detail }))
}

async function handleErrorResponse(response) {
  try {
    const data = await response.json()
    showToast(data.error || data.errors?.join(", ") || "Request failed", "error")
  } catch {
    showToast("Request failed", "error")
  }
}

export async function sendRequest(controller, url, method, formData) {
  try {
    dispatchSaveIndicator("saving")

    const { response, renderedTurboStream } = await turboRequest(url, {
      method,
      accept: "text/vnd.turbo-stream.html, text/html, application/json",
      body: formData
    })

    if (response.ok) {
      // Note: preset apply replaces the entire right sidebar via Turbo Stream.
      // Dispatch asynchronously so the new `save-indicator` controller is connected.
      setTimeout(() => dispatchSaveIndicator("saved"), 0)
      if (!renderedTurboStream) {
        window.location.reload()
      }
      return true
    }

    setTimeout(() => dispatchSaveIndicator("error"), 0)
    if (renderedTurboStream) return false

    await handleErrorResponse(response)
    return false
  } catch (error) {
    logger.error("Request failed:", error)
    showToast("Request failed. Please try again.", "error")
    setTimeout(() => dispatchSaveIndicator("error"), 0)
    return false
  }
}
