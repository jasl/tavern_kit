import logger from "../../logger"

export function areCandidatesVisible(controller) {
  return controller.hasCandidatesContainerTarget
    && !controller.candidatesContainerTarget.classList.contains("hidden")
}

export function getCandidateButtons(controller) {
  if (!controller.hasCandidatesListTarget) return []
  return Array.from(controller.candidatesListTarget.querySelectorAll("button[data-text]"))
}

export function selectCandidateByIndex(controller, index) {
  const candidates = getCandidateButtons(controller)
  if (!candidates[index]) return

  const text = candidates[index].dataset.text
  if (controller.hasTextareaTarget) {
    controller.textareaTarget.value = text
    controller.textareaTarget.focus()
  }

  clearCandidates(controller)
}

export function clearCandidates(controller) {
  if (controller.hasCandidatesListTarget) {
    controller.candidatesListTarget.replaceChildren()
  }

  // Hide error indicator when clearing candidates
  controller.hideErrorIndicator()
  controller.hideLoadingIndicator()

  if (controller.hasCandidatesContainerTarget) {
    controller.candidatesContainerTarget.classList.add("hidden")
  }
}

export function handleCopilotCandidate(controller, data) {
  if (data.generation_id !== controller.generationIdValue) return

  if (controller.hasCandidatesContainerTarget) {
    controller.candidatesContainerTarget.classList.remove("hidden")
  }

  // Hide loading indicator when first candidate arrives
  controller.hideLoadingIndicator()

  const template = document.getElementById("copilot_candidate_template")
  if (!template) {
    logger.warn("[copilot] Candidate template not found")
    return
  }

  const currentCount = getCandidateButtons(controller).length
  const displayIndex = currentCount + 1

  const btn = template.content.cloneNode(true).firstElementChild
  btn.querySelector("[data-candidate-index]").textContent = displayIndex
  btn.querySelector("[data-candidate-text]").textContent = data.text
  btn.dataset.text = data.text

  if (controller.hasCandidatesListTarget) {
    controller.candidatesListTarget.appendChild(btn)
  }
}

export function selectCandidate(controller, event) {
  const text = event.currentTarget.dataset.text
  if (!text) return

  if (controller.hasTextareaTarget) {
    controller.textareaTarget.value = text
    controller.textareaTarget.focus()
  }

  clearCandidates(controller)
}

export function handleInput(controller) {
  if (controller.hasTextareaTarget && controller.textareaTarget.value.trim().length > 0) {
    clearCandidates(controller)
  }
}

export function generateWithCount(controller, event) {
  const count = parseInt(event.currentTarget.dataset.count, 10)
  if (count >= 1 && count <= 4) {
    controller.candidateCountValue = count
  }

  document.activeElement?.blur()
  controller.generate()
}
