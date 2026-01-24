import { readMessageMeta } from "../dom"

export function updateButtonVisibility(controller) {
  const meta = readMessageMeta(controller.element)
  const participantId = meta?.participantId
  const role = meta?.role
  const isOwner = participantId && controller.currentMembershipId && participantId === controller.currentMembershipId
  const isTail = controller.isTailMessage()

  const list = controller.messagesList?.()
  const canManageMessages = list?.dataset?.canManageMessages === "true"

  if (controller.hasMeBadgeTarget) {
    controller.meBadgeTarget.classList.toggle("hidden", !isOwner)
  }

  const canEdit = isOwner && isTail && role === "user"
  const canDelete = (role !== "system") && (canManageMessages || isOwner)

  if (controller.hasEditButtonTarget) {
    controller.editButtonTarget.classList.toggle("hidden", !canEdit)
  }
  if (controller.hasDeleteButtonTarget) {
    controller.deleteButtonTarget.classList.toggle("hidden", !canDelete)
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
