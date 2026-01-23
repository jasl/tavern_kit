export function resetState(controller) {
  if (controller.hasInputTarget) {
    controller.inputTarget.value = ""
  }

  if (controller.hasNameInputTarget) {
    const input = controller.nameInputTarget
    input.value = ""
    input.disabled = false
    input.dataset.originalPlaceholder ||= input.getAttribute("placeholder") || ""
    input.setAttribute("placeholder", input.dataset.originalPlaceholder)
  }

  if (controller.hasFileInfoTarget) {
    controller.fileInfoTarget.classList.add("hidden")
  }
  if (controller.hasZoneTarget) {
    controller.zoneTarget.classList.remove("hidden")
  }

  if (controller.hasIdleTarget) {
    controller.idleTarget.classList.remove("hidden")
  }
  if (controller.hasUploadingTarget) {
    controller.uploadingTarget.classList.add("hidden")
  }

  if (controller.hasSubmitBtnTarget) {
    controller.submitBtnTarget.disabled = true
  }
}

export function submitStart(controller) {
  if (controller.hasFileInfoTarget) {
    controller.fileInfoTarget.classList.add("hidden")
  }

  if (controller.hasZoneTarget) {
    controller.zoneTarget.classList.remove("hidden")
  }

  if (controller.hasIdleTarget) {
    controller.idleTarget.classList.add("hidden")
  }
  if (controller.hasUploadingTarget) {
    controller.uploadingTarget.classList.remove("hidden")
  }

  if (controller.hasSubmitBtnTarget) {
    controller.submitBtnTarget.disabled = true
  }
}
