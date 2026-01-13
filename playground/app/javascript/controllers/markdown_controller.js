import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"
import logger from "../logger"
import { escapeHtml } from "../dom_helpers"

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

const MARKDOWN_RENDER_REGISTRY = new WeakMap()
const VIEWPORT_RENDER_MARGIN_PX = 800
let viewportObserver = null

function getViewportObserver() {
  if (viewportObserver) return viewportObserver

  viewportObserver = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue

      const controller = MARKDOWN_RENDER_REGISTRY.get(entry.target)
      if (!controller) continue

      controller.renderNow()
    }
  }, {
    root: null,
    rootMargin: `${VIEWPORT_RENDER_MARGIN_PX}px 0px`,
    threshold: 0
  })

  return viewportObserver
}

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
    this.observedElement = null
    this.lastRenderedRaw = null

    this.scheduleRender()
  }

  disconnect() {
    this.unobserveVisibility()
  }

  rawValueChanged() {
    this.scheduleRender()
  }

  scheduleRender() {
    const rawContent = this.getRawContent()
    if (!rawContent) return

    if (this.lastRenderedRaw === rawContent) return

    const visibilityTarget = this.getVisibilityTarget()
    if (!visibilityTarget) {
      this.renderNow()
      return
    }

    if (this.isNearViewport(visibilityTarget)) {
      this.renderNow()
      return
    }

    this.setFallbackText(rawContent)
    this.observeVisibility(visibilityTarget)
  }

  renderNow() {
    const rawContent = this.getRawContent()
    if (!rawContent) return
    if (this.lastRenderedRaw === rawContent) return

    const html = this.parseMarkdown(rawContent)
    this.setOutput(html)
    this.lastRenderedRaw = rawContent
    this.unobserveVisibility()
  }

  // Private methods

  getVisibilityTarget() {
    if (this.hasOutputTarget) return this.outputTarget
    return null
  }

  isNearViewport(element) {
    try {
      const rect = element.getBoundingClientRect()
      return rect.bottom >= -VIEWPORT_RENDER_MARGIN_PX && rect.top <= window.innerHeight + VIEWPORT_RENDER_MARGIN_PX
    } catch {
      return true
    }
  }

  observeVisibility(element) {
    this.unobserveVisibility()

    this.observedElement = element
    MARKDOWN_RENDER_REGISTRY.set(element, this)
    getViewportObserver().observe(element)
  }

  unobserveVisibility() {
    if (!this.observedElement) return

    MARKDOWN_RENDER_REGISTRY.delete(this.observedElement)
    viewportObserver?.unobserve(this.observedElement)
    this.observedElement = null
  }

  setFallbackText(rawContent) {
    if (!this.hasOutputTarget) return
    if (this.lastRenderedRaw === rawContent) return

    // Only set fallback when output is effectively blank (common: <noscript> only).
    const hasNonNoscriptContent = Array.from(this.outputTarget.childNodes).some((node) => {
      return node.nodeType === Node.ELEMENT_NODE && node.nodeName !== "NOSCRIPT"
    })
    if (hasNonNoscriptContent) return

    this.outputTarget.innerHTML = escapeHtml(rawContent).replace(/\n/g, "<br>")
  }

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
