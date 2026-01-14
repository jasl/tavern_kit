import { Turbo } from "@hotwired/turbo-rails"
import logger from "./logger"
import { railsFetch } from "./rails_request"

const TURBO_STREAM_MIME_TYPE = "text/vnd.turbo-stream.html"
const TOAST_HEADER = "X-TavernKit-Toast"

function isTurboStreamResponse(response) {
  const contentType = response.headers.get("content-type") || ""
  return contentType.includes(TURBO_STREAM_MIME_TYPE) || contentType.includes("turbo-stream")
}

async function renderTurboStreamResponse(response) {
  if (!isTurboStreamResponse(response)) {
    return { rendered: false, turboStreamHtml: null }
  }

  try {
    const turboStreamHtml = await response.text()
    if (turboStreamHtml) {
      Turbo.renderStreamMessage(turboStreamHtml)
    }
    return { rendered: true, turboStreamHtml }
  } catch (error) {
    logger.error("[turbo_fetch] Failed to render Turbo Stream response:", error)
    return { rendered: false, turboStreamHtml: null }
  }
}

/**
 * fetch() wrapper that renders Turbo Stream responses (even on non-2xx statuses).
 *
 * Turbo does not automatically apply Turbo Stream responses returned from fetch(),
 * so any endpoint that responds with Turbo Streams must be handled manually.
 *
 * Why render on non-2xx?
 * - We deliberately allow controllers to return Turbo Stream + error toast/alert with an error status.
 * - Without this, the UI can "silently fail" (status != 2xx, no DOM update).
 *
 * Toast dedupe:
 * - When the server has already rendered a toast via Turbo Stream, it sets `X-TavernKit-Toast: 1`.
 * - Callers can use `toastAlreadyShown` to avoid emitting a duplicate client-side toast.
 */
export async function fetchTurboStream(url, options = {}) {
  const { method = "GET", ...requestOptions } = options
  requestOptions.responseKind ||= "turbo-stream"

  const response = await railsFetch(method, url, requestOptions)
  const toastAlreadyShown = response.headers.get(TOAST_HEADER) === "1"
  const { rendered, turboStreamHtml } = await renderTurboStreamResponse(response)

  return {
    response,
    renderedTurboStream: rendered,
    turboStreamHtml,
    toastAlreadyShown
  }
}
