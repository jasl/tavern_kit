import logger from "./logger"
import { FetchRequest, RequestInterceptor } from "@rails/request.js"

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
