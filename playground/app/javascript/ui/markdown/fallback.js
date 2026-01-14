import { escapeHtml } from "../../dom_helpers"

export function setFallbackText(controller, rawContent) {
  if (!controller.hasOutputTarget) return
  if (controller.lastRenderedRaw === rawContent) return

  // Only set fallback when output is effectively blank (common: <noscript> only).
  const hasNonNoscriptContent = Array.from(controller.outputTarget.childNodes).some((node) => {
    return node.nodeType === Node.ELEMENT_NODE && node.nodeName !== "NOSCRIPT"
  })
  if (hasNonNoscriptContent) return

  controller.outputTarget.innerHTML = escapeHtml(rawContent).replace(/\n/g, "<br>")
}
