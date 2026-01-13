import { assignNested } from "./nested"

export function buildPatchesFromChanges(pendingChanges) {
  const settingsPatch = {}
  const dataPatch = {}
  const columns = {}

  pendingChanges.forEach((change) => {
    if (change.path && change.path.startsWith("settings.")) {
      assignNested(settingsPatch, change.path.replace(/^settings\./, ""), change.value)
    } else if (change.path && change.path.startsWith("data.")) {
      assignNested(dataPatch, change.path.replace(/^data\./, ""), change.value)
    } else if (change.path) {
      columns[change.path] = change.value
    }
  })

  const hasSettings = Object.keys(settingsPatch).length > 0
  const hasData = Object.keys(dataPatch).length > 0
  const hasColumns = Object.keys(columns).length > 0

  return { settingsPatch, dataPatch, columns, hasSettings, hasData, hasColumns }
}
