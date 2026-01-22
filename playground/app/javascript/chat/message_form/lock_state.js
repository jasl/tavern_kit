export function updateLockedState(controller) {
  const isGenerationLocked = controller.rejectPolicyValue && controller.schedulingStateValue === "ai_generating"
  const shouldDisableTextarea = controller.spaceReadOnlyValue || isGenerationLocked
  const shouldDisableSendBtn = shouldDisableTextarea || controller.cableConnectedValue === false

  if (controller.hasTextareaTarget) {
    controller.textareaTarget.disabled = shouldDisableTextarea

    if (isGenerationLocked) {
      const lockedPlaceholder = controller.textareaTarget.dataset.lockedPlaceholder
      if (lockedPlaceholder) {
        controller.textareaTarget.placeholder = lockedPlaceholder
      }
    } else {
      const defaultPlaceholder = controller.textareaTarget.dataset.defaultPlaceholder
      if (defaultPlaceholder) {
        controller.textareaTarget.placeholder = defaultPlaceholder
      }
    }
  }

  if (controller.hasSendBtnTarget) {
    controller.sendBtnTarget.disabled = shouldDisableSendBtn
  }

  if (controller.hasGeneratingAlertTarget) {
    controller.generatingAlertTarget.classList.toggle("hidden", controller.schedulingStateValue !== "ai_generating")
  }

  if (controller.hasCableDisconnectAlertTarget) {
    controller.cableDisconnectAlertTarget.classList.toggle("hidden", controller.cableConnectedValue !== false)
  }
}
