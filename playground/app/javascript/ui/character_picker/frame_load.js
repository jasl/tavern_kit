import { updateFilterLinks } from "./links"
import { syncCheckboxes, updateCounter } from "./ui_sync"

export function handleFrameLoad(controller) {
  requestAnimationFrame(() => {
    syncCheckboxes(controller)
    updateCounter(controller)
    updateFilterLinks(controller)
  })
}
