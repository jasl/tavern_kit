import { jsonPatch } from "../../request_helpers"

export async function savePatch(controller, url, settingsPatch, dataPatch, columns = {}, attemptedConflictRetry = false) {
  const { response, data: result } = await jsonPatch(url, {
    body: {
      schema_version: controller.schemaVersionValue,
      settings_version: controller.settingsVersionValue,
      ...columns,
      ...(Object.keys(settingsPatch).length ? { settings: settingsPatch } : {}),
      ...(Object.keys(dataPatch).length ? { data: dataPatch } : {})
    }
  })

  if (!result) {
    throw new Error("Save failed")
  }

  if (response.status === 409 && result?.conflict === true && attemptedConflictRetry === false) {
    const nextVersion = result?.[controller.resourceKeyValue]?.settings_version
    if (typeof nextVersion === "number") {
      controller.settingsVersionValue = nextVersion
      return savePatch(controller, url, settingsPatch, dataPatch, columns, true)
    }
  }

  if (!response.ok || !result.ok) {
    throw new Error(result.errors?.join(", ") || "Save failed")
  }

  const resource = result?.[controller.resourceKeyValue]
  if (typeof resource?.settings_version === "number") {
    controller.settingsVersionValue = resource.settings_version
  }

  controller.dispatch("saved", { detail: { key: controller.resourceKeyValue, resource, result } })

  if (controller.resourceKeyValue === "participant" && result?.participant) {
    controller.dispatch("participantUpdated", { detail: { participant: result.participant } })
  }

  if (controller.resourceKeyValue === "space_membership" && result?.space_membership) {
    controller.dispatch("spaceMembershipUpdated", { detail: { space_membership: result.space_membership } })
  }

  return result
}
