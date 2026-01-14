import { Controller } from "@hotwired/stimulus"
import { setFallbackText } from "../ui/markdown/fallback"
import { configureMarkedOnce, parseMarkdown } from "../ui/markdown/marked"
import { setOutput } from "../ui/markdown/output"
import { isNearViewport, observeVisibility } from "../ui/markdown/visibility"

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
    configureMarkedOnce()
    this.disconnectVisibility = null
    this.lastRenderedRaw = null

    this.scheduleRender()
  }

  disconnect() {
    this.disconnectVisibility?.()
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

    if (isNearViewport(visibilityTarget)) {
      this.renderNow()
      return
    }

    setFallbackText(this, rawContent)
    this.disconnectVisibility?.()
    this.disconnectVisibility = observeVisibility(visibilityTarget, () => this.renderNow())
  }

  renderNow() {
    const rawContent = this.getRawContent()
    if (!rawContent) return
    if (this.lastRenderedRaw === rawContent) return

    const html = parseMarkdown(rawContent)
    setOutput(this, html)
    this.lastRenderedRaw = rawContent
    this.disconnectVisibility?.()
    this.disconnectVisibility = null
  }

  // Private methods

  getVisibilityTarget() {
    if (this.hasOutputTarget) return this.outputTarget
    return null
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

}
