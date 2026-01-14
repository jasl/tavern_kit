import { turboRequest } from "../../request_helpers"

/**
 * Refresh a Turbo Frame in-place.
 *
 * Behavior:
 * - If the endpoint returns a Turbo Stream response, we render it and stop.
 * - Otherwise we expect HTML containing the requested frame and update its contents.
 *
 * Notes:
 * - We prefer Turbo Streams for "source of truth" UI updates.
 * - The fallback uses `innerHTML` intentionally, because the HTML comes from our server
 *   and is scoped to the frame subtree (this is not "JS string template" rendering).
 */
export async function refreshTurboFrame(frameId, url, headers = {}) {
  if (!frameId) return { ok: false, reason: "missing_frame_id" }

  const frame = document.getElementById(frameId)
  if (!frame) return { ok: false, reason: "missing_frame" }

  const { response, renderedTurboStream } = await turboRequest(url, {
    headers: {
      "Accept": "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
      "Turbo-Frame": frameId,
      ...headers
    }
  })

  if (renderedTurboStream) {
    return { ok: true, renderedTurboStream: true }
  }

  if (!response.ok) {
    return { ok: false, response }
  }

  const html = await response.text()
  const doc = new DOMParser().parseFromString(html, "text/html")
  const newFrame = doc.getElementById(frameId)

  if (newFrame) {
    frame.innerHTML = newFrame.innerHTML
  }

  return { ok: true, renderedTurboStream: false }
}
