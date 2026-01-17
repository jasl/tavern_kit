import { showToast } from "../../request_helpers"
import { closeSaveModal } from "./modal"
import { sendRequest } from "./requests"

export async function savePreset(controller) {
  const isCreateMode = controller.hasModeCreateTarget && controller.modeCreateTarget.checked
  if (isCreateMode) {
    await createPreset(controller)
  } else {
    await updatePreset(controller)
  }
}

async function createPreset(controller) {
  const name = controller.hasNameInputTarget ? controller.nameInputTarget.value.trim() : ""

  if (!name) {
    showToast("Please enter a preset name", "warning")
    if (controller.hasNameInputTarget) controller.nameInputTarget.focus()
    return
  }

  const formData = new FormData()
  formData.append("preset[name]", name)
  formData.append("preset[membership_id]", controller.membershipIdValue)

  const success = await sendRequest(controller, "/presets", "POST", formData)
  if (success) closeSaveModal(controller)
}

async function updatePreset(controller) {
  const presetId = controller.currentPresetIdValue

  if (!presetId) {
    showToast("No preset selected", "warning")
    return
  }

  const formData = new FormData()
  formData.append("membership_id", controller.membershipIdValue)

  const success = await sendRequest(controller, `/presets/${presetId}`, "PATCH", formData)
  if (success) closeSaveModal(controller)
}
