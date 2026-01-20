import { SCHEDULING_STATE_CHANGED_EVENT, dispatchWindowEvent } from "../events"

export function handleQueueUpdated(controller, data) {
  const {
    scheduling_state: schedulingState,
    group_queue_revision: groupQueueRevision,
    reject_policy: rejectPolicy,
    during_generation_user_input_policy: duringGenerationUserInputPolicy,
    paused_reason: pausedReason,
    paused_speaker_name: pausedSpeakerName
  } = data
  const revision = Number(groupQueueRevision)

  // In multi-process setups, ActionCable events can arrive out of order.
  // Use the server-side monotonic revision (shared with Turbo updates) to ignore stale events.
  if (Number.isFinite(revision)) {
    if (Number.isFinite(controller.lastQueueRevision) && revision <= controller.lastQueueRevision) {
      return
    }
    controller.lastQueueRevision = revision
  }

  dispatchWindowEvent(SCHEDULING_STATE_CHANGED_EVENT, {
    schedulingState,
    rejectPolicy,
    duringGenerationUserInputPolicy,
    conversationId: controller.conversationValue
  })

  if (schedulingState === "paused" && pausedReason === "user_stop") {
    controller.hideIdleAlert?.()
    controller.showStopDecisionAlert?.({ paused_reason: pausedReason, paused_speaker_name: pausedSpeakerName })
  } else {
    controller.hideStopDecisionAlert?.()
  }
}
