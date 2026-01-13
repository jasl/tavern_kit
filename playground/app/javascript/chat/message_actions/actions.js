import logger from "../../logger"
import { showToast } from "../../request_helpers"
import { copyTextToClipboard } from "../../dom_helpers"
import { getMessageContent } from "./content"

export async function copy(controller, event) {
  event.preventDefault()

  const content = getMessageContent(controller)
  if (!content) return

  try {
    const ok = await copyTextToClipboard(content)
    if (!ok) {
      logger.error("Failed to copy to clipboard")
    }
    showToast(ok ? "Copied to clipboard" : "Failed to copy", ok ? "success" : "error")
  } catch (error) {
    logger.error("Failed to copy:", error)
    showToast("Failed to copy", "error")
  }
}

export function regenerate(_controller, event) {
  const button = event.currentTarget
  const icon = button.querySelector("span[class*='icon-']")

  if (icon) {
    icon.classList.add("animate-spin")
  }
}

export function triggerBranch(controller, event) {
  event.preventDefault()

  if (controller.hasBranchBtnTarget) {
    controller.branchBtnTarget.click()
  } else {
    showToast("Branch action not available", "warning")
  }
}

export function showDebug(controller, event) {
  event.preventDefault()

  const button = event.currentTarget
  const runDataJson = button.dataset.runData

  if (!runDataJson) {
    showToast("No debug data available", "warning")
    return
  }

  let runData
  try {
    runData = JSON.parse(runDataJson)
  } catch (e) {
    logger.error("Failed to parse run data:", e)
    showToast("Failed to load debug data", "error")
    return
  }

  const modal = document.getElementById("run_detail_modal")
  if (!modal) {
    logger.error("Run detail modal not found")
    showToast("Debug modal not found", "error")
    return
  }

  const modalController = controller.application.getControllerForElementAndIdentifier(modal, "run-detail-modal")
  if (modalController) {
    modalController.showRun(runData)
  } else {
    logger.error("Run detail modal controller not found")
    showToast("Debug modal controller not found", "error")
  }
}

