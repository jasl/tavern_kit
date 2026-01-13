import { showToast } from "../../request_helpers"

export function handleRunSkipped(reason, message = null) {
  const toastMessage = message || getSkippedReasonMessage(reason)
  showToast(toastMessage, "warning")
}

export function handleRunCanceled() {
  showToast("Stopped.", "info")
}

export function handleRunFailed(_code, message) {
  const toastMessage = message || "Generation failed. Please try again."
  showToast(toastMessage, "error")
}

export function getSkippedReasonMessage(reason) {
  const messages = {
    "message_mismatch": "Skipped: conversation has changed since your request.",
    "state_changed": "Skipped: conversation state changed.",
  }
  return messages[reason] || "Operation skipped due to a state change."
}
