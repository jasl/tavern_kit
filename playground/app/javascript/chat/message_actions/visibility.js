import { readMessageMeta } from "../dom"

export function updateButtonVisibility(controller) {
  const meta = readMessageMeta(controller.element)
  const participantId = meta?.participantId
  const role = meta?.role
  const isOwner = participantId && controller.currentMembershipId && participantId === controller.currentMembershipId
  const isTail = controller.isTailMessage()

  const canEditDelete = isOwner && isTail && role === "user"

  if (controller.hasEditButtonTarget) {
    controller.editButtonTarget.classList.toggle("hidden", !canEditDelete)
  }
  if (controller.hasDeleteButtonTarget) {
    controller.deleteButtonTarget.classList.toggle("hidden", !canEditDelete)
  }

  const showBranchCta = isOwner && !isTail && role === "user"

  if (controller.hasBranchCtaTarget) {
    controller.branchCtaTarget.classList.toggle("hidden", !showBranchCta)
  }

  const canSwipe = isTail && role === "assistant"

  if (controller.hasSwipeNavTarget) {
    controller.swipeNavTarget.classList.toggle("hidden", !canSwipe)
  }

  if (controller.hasRegenerateButtonTarget) {
    controller.regenerateButtonTarget.title = isTail
      ? "Regenerate"
      : "Regenerate (creates branch)"
  }
}
