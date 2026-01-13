import logger from "../../logger"
import { getInputValue } from "./inputs"
import { buildPatchesFromChanges } from "./patch_builder"
import { savePatch } from "./requests"
import { applyServerResource } from "./resource_sync"
import { updateStatus } from "./status_badge"

export function saveNow(controller) {
  if (controller.saveTimeout) {
    clearTimeout(controller.saveTimeout)
  }
  performSave(controller)
}

export function scheduleChange(controller, input) {
  const key = input.dataset.settingKey
  const path = input.dataset.settingPath
  const type = input.dataset.settingType
  const value = getInputValue(input, type)

  controller.pendingChanges.set(path || key, { key, path, type, value })

  updateStatus(controller, "pending")

  if (path === "llm_provider_id") {
    saveNow(controller)
    return
  }

  if (controller.saveTimeout) clearTimeout(controller.saveTimeout)
  controller.saveTimeout = setTimeout(() => performSave(controller), controller.debounceValue)
}

export async function performSave(controller) {
  if (controller.pendingChanges.size === 0 || controller.isSaving) return

  controller.isSaving = true
  updateStatus(controller, "saving")

  const { settingsPatch, dataPatch, columns, hasSettings, hasData, hasColumns } = buildPatchesFromChanges(controller.pendingChanges)

  if (!hasSettings && !hasData && !hasColumns) {
    controller.pendingChanges.clear()
    controller.isSaving = false
    updateStatus(controller, "saved")
    return
  }

  try {
    const result = await savePatch(controller, controller.urlValue, settingsPatch, dataPatch, columns)
    applyServerResource(controller, result?.[controller.resourceKeyValue])

    controller.pendingChanges.clear()
    updateStatus(controller, "saved")

    if (controller.hasSavedAtTarget) {
      controller.savedAtTarget.textContent = new Date().toLocaleTimeString()
    }
  } catch (error) {
    logger.error("Settings save failed:", error)
    updateStatus(controller, "error", error.message)
  } finally {
    controller.isSaving = false
  }
}
