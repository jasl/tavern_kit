import logger from "../../logger"
import { jsonRequest } from "../../request_helpers"
import { clearCandidates } from "./candidates"
import { generateUUID } from "./uuid"

export async function generate(controller) {
  if (controller.fullValue || controller.generatingValue) return

  controller.generatingValue = true
  updateGenerateButtonState(controller)
  clearCandidates(controller)
  controller.generationIdValue = generateUUID()

  // Show candidates container with loading indicator

  if (controller.hasCandidatesContainerTarget) {
    controller.candidatesContainerTarget.classList.remove("hidden")
  }
  controller.showLoadingIndicator()

  try {
    const { response, data: error } = await jsonRequest(controller.urlValue, {
      method: "POST",
      body: {
        candidate_count: controller.candidateCountValue,
        generation_id: controller.generationIdValue
      }
    })

    if (!response.ok) {
      const errorMessage = error?.error || `Request failed (${response.status})`
      logger.error("Generation failed:", errorMessage)
      controller.showErrorIndicator(errorMessage)
      resetGenerateButton(controller)
    }
  } catch (error) {
    logger.error("Generation request failed:", error)
    controller.showErrorIndicator(error.message || "Network error")
    resetGenerateButton(controller)
  }
}

export function updateGenerateButtonState(controller) {
  if (controller.hasGenerateBtnTarget) {
    controller.generateBtnTarget.disabled = true
  }
  if (controller.hasGenerateIconTarget) {
    controller.generateIconTarget.classList.add("hidden")
  }
  if (controller.hasGenerateSpinnerTarget) {
    controller.generateSpinnerTarget.classList.remove("hidden")
  }
  if (controller.hasGenerateTextTarget) {
    controller.generateTextTarget.textContent = "Generating..."
  }
  if (controller.hasCountBtnTarget) {
    controller.countBtnTarget.disabled = true
  }
}

export function resetGenerateButton(controller) {
  controller.generatingValue = false

  if (controller.hasGenerateBtnTarget) {
    controller.generateBtnTarget.disabled = controller.fullValue
  }
  if (controller.hasGenerateIconTarget) {
    controller.generateIconTarget.classList.remove("hidden")
  }
  if (controller.hasGenerateSpinnerTarget) {
    controller.generateSpinnerTarget.classList.add("hidden")
  }
  if (controller.hasGenerateTextTarget) {
    controller.generateTextTarget.textContent = "Vibe"
  }
  if (controller.hasCountBtnTarget) {
    controller.countBtnTarget.disabled = controller.fullValue
  }
}
