export function escapeHtml(value) {
  const div = document.createElement("div")
  div.textContent = value == null ? "" : String(value)
  return div.innerHTML
}

function fallbackCopyTextToClipboard(text) {
  const textarea = document.createElement("textarea")
  textarea.value = text
  textarea.setAttribute("readonly", "")
  textarea.style.position = "fixed"
  textarea.style.left = "-9999px"
  textarea.style.top = "-9999px"
  document.body.appendChild(textarea)
  textarea.focus()
  textarea.select()

  try {
    return document.execCommand("copy")
  } catch {
    return false
  } finally {
    document.body.removeChild(textarea)
  }
}

export async function copyTextToClipboard(text) {
  const value = text == null ? "" : String(text)
  if (!value) return false

  try {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(value)
      return true
    }
  } catch {
    // Fall back to execCommand-based copy for older browsers / insecure contexts.
  }

  return fallbackCopyTextToClipboard(value)
}
