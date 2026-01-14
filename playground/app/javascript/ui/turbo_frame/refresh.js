import { turboRequest } from "../../request_helpers"

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
