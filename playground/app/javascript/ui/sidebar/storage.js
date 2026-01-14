export function storageKey(controller) {
  return `sidebar-${controller.keyValue}`
}

export function shouldPersistState() {
  return window.innerWidth >= 1024
}

export function loadState(controller) {
  if (!controller.hasToggleTarget) return

  const savedState = localStorage.getItem(storageKey(controller))

  if (savedState !== null && shouldPersistState()) {
    controller.toggleTarget.checked = savedState === "open"
  }
}

export function saveState(controller) {
  if (!controller.hasToggleTarget) return

  const state = controller.toggleTarget.checked ? "open" : "closed"
  localStorage.setItem(storageKey(controller), state)
}
