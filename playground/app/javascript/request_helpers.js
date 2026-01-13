import logger from "./logger"
import { fetchTurboStream } from "./turbo_fetch"

const requestLocks = new Map()

export function getCsrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.content || ""
}

export function showToast(message, type = "info", duration = 3000) {
  if (!message) return

  window.dispatchEvent(new CustomEvent("toast:show", {
    detail: { message, type, duration },
    bubbles: true,
    cancelable: true
  }))
}

export function showToastIfNeeded(toastAlreadyShown, message, type = "error", duration = 3000) {
  if (toastAlreadyShown) return
  showToast(message, type, duration)
}

/**
 * Ensure only one request runs at a time for the same key.
 *
 * - Key should be stable across Turbo Stream replacements (URLs are ideal).
 * - Prevents double-click race conditions in Stimulus controllers.
 */
export async function withRequestLock(key, fn) {
  const lockKey = String(key || "")
  if (!lockKey) {
    return { skipped: false, value: await fn() }
  }

  if (requestLocks.get(lockKey)) {
    return { skipped: true, value: null }
  }

  requestLocks.set(lockKey, true)
  try {
    return { skipped: false, value: await fn() }
  } finally {
    requestLocks.delete(lockKey)
  }
}

export async function turboRequest(url, options = {}) {
  const method = options.method || "GET"
  const csrfToken = options.csrfToken ?? getCsrfToken()
  const accept = options.accept || "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"
  const headers = { ...(options.headers || {}) }

  headers.Accept ||= accept

  // Rails only requires CSRF token for non-GET requests, but sending it is harmless.
  if (csrfToken && !headers["X-CSRF-Token"]) {
    headers["X-CSRF-Token"] = csrfToken
  }

  return fetchTurboStream(url, {
    ...options,
    method,
    headers
  })
}

export async function turboPost(url, options = {}) {
  return turboRequest(url, { ...options, method: "POST" })
}

async function parseResponseJsonSafely(response) {
  const text = await response.text()
  if (!text) return null

  try {
    return JSON.parse(text)
  } catch {
    return null
  }
}

export async function jsonRequest(url, options = {}) {
  const method = options.method || "GET"
  const csrfToken = options.csrfToken ?? getCsrfToken()
  const accept = options.accept || "application/json"
  const headers = { ...(options.headers || {}) }

  headers.Accept ||= accept

  // Rails only requires CSRF token for non-GET requests, but sending it is harmless.
  if (csrfToken && !headers["X-CSRF-Token"]) {
    headers["X-CSRF-Token"] = csrfToken
  }

  const body = (() => {
    if (!("body" in options)) return undefined

    const rawBody = options.body
    if (rawBody === null || rawBody === undefined) return rawBody
    if (typeof rawBody === "string") return rawBody
    if (rawBody instanceof FormData) return rawBody
    if (rawBody instanceof URLSearchParams) return rawBody

    headers["Content-Type"] ||= "application/json"
    return JSON.stringify(rawBody)
  })()

  const response = await fetch(url, {
    ...options,
    method,
    headers,
    body
  })

  const data = await parseResponseJsonSafely(response.clone())
  return { response, data }
}

export async function jsonPatch(url, options = {}) {
  return jsonRequest(url, { ...options, method: "PATCH" })
}

/**
 * Disable a button immediately and re-enable it only when the request fails.
 * On success, we keep it disabled because Turbo Streams typically replace the DOM anyway.
 */
export async function disableUntilReplaced(button, fn) {
  if (!button) return fn()

  const wasDisabled = button.disabled
  button.disabled = true

  try {
    const ok = await fn()
    if (!ok) button.disabled = wasDisabled
    return ok
  } catch (error) {
    button.disabled = wasDisabled
    logger.error("[request_helpers] Request failed:", error)
    throw error
  }
}
