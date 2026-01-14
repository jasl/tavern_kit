export function openSaveModal(controller) {
  if (!controller.hasModalTarget) return

  if (controller.hasModeUpdateTarget) {
    controller.modeUpdateTarget.checked = true
  }

  toggleMode(controller)
  controller.modalTarget.showModal()
}

export function closeSaveModal(controller) {
  if (!controller.hasModalTarget) return
  controller.modalTarget.close()
}

export function toggleMode(controller) {
  const isCreateMode = controller.hasModeCreateTarget && controller.modeCreateTarget.checked

  if (controller.hasNameFieldTarget) {
    controller.nameFieldTarget.classList.toggle("hidden", !isCreateMode)
  }

  if (controller.hasNameInputTarget && !isCreateMode) {
    controller.nameInputTarget.value = ""
  }
}
