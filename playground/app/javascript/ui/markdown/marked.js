import { marked } from "marked"
import logger from "../../logger"
import { escapeHtml } from "../../dom_helpers"

const SAFE_LINK_PROTOCOLS = new Set(["http:", "https:", "mailto:", "tel:"])
const SAFE_IMAGE_PROTOCOLS = new Set(["http:", "https:"])

function sanitizeUrl(href, allowedProtocols) {
  if (!href) return null

  try {
    const url = new URL(String(href), window.location.href)
    if (!allowedProtocols.has(url.protocol)) return null
    return url
  } catch {
    return null
  }
}

let markedConfigured = false

export function configureMarkedOnce() {
  if (markedConfigured) return

  const renderer = new marked.Renderer()

  // Disallow raw HTML from user content (XSS mitigation).
  renderer.html = (html) => escapeHtml(html)

  // Sanitize links to block javascript:/data: etc.
  renderer.link = (href, title, text) => {
    const url = sanitizeUrl(href, SAFE_LINK_PROTOCOLS)
    const safeText = escapeHtml(text)
    if (!url) return safeText

    const isExternal = url.origin !== window.location.origin
    const safeHref = escapeHtml(url.toString())
    const safeTitle = title ? ` title="${escapeHtml(title)}"` : ""
    const externalAttrs = isExternal ? ` target="_blank" rel="nofollow noreferrer noopener"` : ""

    return `<a href="${safeHref}"${safeTitle}${externalAttrs}>${safeText}</a>`
  }

  // Allow only http(s) images (blocks data: and other schemes).
  renderer.image = (href, title, text) => {
    const url = sanitizeUrl(href, SAFE_IMAGE_PROTOCOLS)
    if (!url) return ""

    const safeSrc = escapeHtml(url.toString())
    const safeAlt = escapeHtml(text)
    const safeTitle = title ? ` title="${escapeHtml(title)}"` : ""

    return `<img src="${safeSrc}" alt="${safeAlt}" loading="lazy" referrerpolicy="no-referrer"${safeTitle} />`
  }

  marked.setOptions({
    gfm: true,        // GitHub Flavored Markdown
    breaks: true,     // Convert \n to <br>
    pedantic: false,
    headerIds: false, // Don't add IDs to headers
    mangle: false,    // Don't escape autolinks
    renderer
  })

  markedConfigured = true
}

export function parseMarkdown(text) {
  try {
    return marked.parse(text)
  } catch (error) {
    logger.error("Markdown parsing error:", error)
    return escapeHtml(text)
  }
}
