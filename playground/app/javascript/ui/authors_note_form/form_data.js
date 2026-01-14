export function collectFormData(controller) {
  const settings = {}

  if (controller.hasEnableToggleTarget) {
    settings.use_character_authors_note = controller.enableToggleTarget.checked
  }

  if (controller.hasContentTarget) {
    settings.authors_note = controller.contentTarget.value
  }

  if (controller.hasPositionTarget) {
    settings.authors_note_position = controller.positionTarget.value
  }

  if (controller.hasDepthTarget) {
    const depth = parseInt(controller.depthTarget.value, 10)
    settings.authors_note_depth = isNaN(depth) ? 4 : Math.max(0, depth)
  }

  if (controller.hasRoleTarget) {
    settings.authors_note_role = controller.roleTarget.value
  }

  if (controller.hasCombineModeTarget) {
    settings.character_authors_note_position = controller.combineModeTarget.value
  }

  return settings
}
