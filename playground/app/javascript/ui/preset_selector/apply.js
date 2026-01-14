import { sendRequest } from "./requests"

export async function applyPresetById(controller, presetId) {
  const formData = new FormData()
  formData.append("preset_id", presetId)
  formData.append("membership_id", controller.membershipIdValue)

  await sendRequest(controller.applyUrlValue, "POST", formData)
}
