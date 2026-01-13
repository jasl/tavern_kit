import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"
import logger from "../logger"

const SAFE_LINK_PROTOCOLS = new Set(["http:", "https:", "mailto:", "tel:"])
const SAFE_IMAGE_PROTOCOLS = new Set(["http:", "https:"])

function escapeHtml(text) {
  const div = document.createElement("div")
  div.textContent = text == null ? "" : String(text)
  return div.innerHTML
}

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

/**
 * Markdown Controller
 *
 * Renders markdown content using marked.js library.
 * Configured with safe defaults to prevent XSS.
 */
export default class extends Controller {
  static targets = ["content", "output"]
  static values = {
    raw: String
  }

  connect() {
    this.configureMarked()
    this.render()
  }

  rawValueChanged() {
    this.render()
  }

  render() {
    const rawContent = this.getRawContent()
    if (!rawContent) return

    const html = this.parseMarkdown(rawContent)
    this.setOutput(html)
  }

  // Private methods

  configureMarked() {
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

  getRawContent() {
    // Priority: value > content target text
    if (this.hasRawValue && this.rawValue) {
      return this.rawValue
    }

    if (this.hasContentTarget) {
      // Handle <template> elements which store content in .content property
      if (this.contentTarget.tagName === "TEMPLATE") {
        return this.contentTarget.content.textContent
      }
      return this.contentTarget.textContent
    }

    return this.element.dataset.markdownContent || ""
  }

  parseMarkdown(text) {
    try {
      return marked.parse(text)
    } catch (error) {
      logger.error("Markdown parsing error:", error)
      return escapeHtml(text)
    }
  }

  setOutput(html) {
    if (this.hasOutputTarget) {
      this.outputTarget.innerHTML = html
    } else if (this.hasContentTarget) {
      // If no output target, replace content target's sibling or create one
      let output = this.contentTarget.nextElementSibling
      if (!output || !output.classList.contains("markdown-output")) {
        output = document.createElement("div")
        output.classList.add("markdown-output", "prose", "prose-sm", "max-w-none")
        this.contentTarget.after(output)
      }
      output.innerHTML = html
      this.contentTarget.classList.add("hidden")
    } else {
      // Fallback: render directly in the element
      this.element.innerHTML = html
    }
  }

  escapeHtml(text) {
    return escapeHtml(text)
  }
}
