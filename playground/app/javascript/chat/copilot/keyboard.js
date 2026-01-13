import { areCandidatesVisible, clearCandidates, getCandidateButtons, selectCandidateByIndex } from "./candidates"

export function handleKeydown(controller, event) {
  if (!areCandidatesVisible(controller)) return

  const isTyping = controller.hasTextareaTarget
    && document.activeElement === controller.textareaTarget
    && controller.textareaTarget.value.trim().length > 0

  if (event.key === "Escape") {
    event.preventDefault()
    clearCandidates(controller)
    return
  }

  if (!isTyping && event.key >= "1" && event.key <= "4") {
    const index = parseInt(event.key, 10) - 1
    const candidates = getCandidateButtons(controller)
    if (candidates[index]) {
      event.preventDefault()
      selectCandidateByIndex(controller, index)
    }
  }
}

