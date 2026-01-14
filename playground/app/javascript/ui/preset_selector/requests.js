import logger from "../../logger"
import { showToast, turboRequest } from "../../request_helpers"

async function handleErrorResponse(response) {
  try {
    const data = await response.json()
    showToast(data.error || data.errors?.join(", ") || "Request failed", "error")
  } catch {
    showToast("Request failed", "error")
  }
}

export async function sendRequest(url, method, formData) {
  try {
    const { response, renderedTurboStream } = await turboRequest(url, {
      method,
      accept: "text/vnd.turbo-stream.html, text/html, application/json",
      body: formData
    })

    if (response.ok) {
      if (!renderedTurboStream) {
        window.location.reload()
      }
      return true
    }

    if (renderedTurboStream) return false

    await handleErrorResponse(response)
    return false
  } catch (error) {
    logger.error("Request failed:", error)
    showToast("Request failed. Please try again.", "error")
    return false
  }
}
