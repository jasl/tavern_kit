export function getTabTarget(controller, tab) {
  switch (tab) {
    case "basic": return controller.hasBasicTarget ? controller.basicTarget : null
    case "prompts": return controller.hasPromptsTarget ? controller.promptsTarget : null
    case "authors_note": return controller.hasAuthors_noteTarget ? controller.authors_noteTarget : null
    case "more": return controller.hasMoreTarget ? controller.moreTarget : null
    default: return null
  }
}
