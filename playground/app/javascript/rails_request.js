import logger from "./logger"
import { FetchRequest, RequestInterceptor } from "@rails/request.js"

/**
 * railsFetch
 *
 * Thin wrapper around `@rails/request.js` that:
 * - Lets request.js derive CSRF token + default headers (and apply interceptors)
 * - Uses `Turbo.fetch` when available (so cookies/redirects behave consistently with Turbo)
 *
 * We intentionally do NOT use `FetchRequest#perform()` here because we need custom handling
 * for Turbo Stream responses (see `fetchTurboStream()`), including rendering on non-2xx.
 */
export async function railsFetch(method, url, options = {}) {
  const request = new FetchRequest(method, url, options)

  try {
    const interceptor = RequestInterceptor.get()
    if (interceptor) {
      await interceptor(request)
    }
  } catch (error) {
    logger.error("[rails_request] Request interceptor failed:", error)
  }

  const fetchFn = window.Turbo?.fetch || window.fetch
  return fetchFn(request.url, request.fetchOptions)
}
