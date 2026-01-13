import { SCHEDULING_STATE_CHANGED_EVENT, dispatchWindowEvent } from "../events"

export function handleQueueUpdated(controller, data) {
  const { scheduling_state: schedulingState, group_queue_revision: groupQueueRevision } = data
  const revision = Number(groupQueueRevision)

  // In multi-process setups, ActionCable events can arrive out of order.
  // Use the server-side monotonic revision (shared with Turbo updates) to ignore stale events.
  if (Number.isFinite(revision)) {
    if (Number.isFinite(controller.lastQueueRevision) && revision <= controller.lastQueueRevision) {
      return
    }
    controller.lastQueueRevision = revision
  }

  if (schedulingState) {
    dispatchWindowEvent(SCHEDULING_STATE_CHANGED_EVENT, { schedulingState, conversationId: controller.conversationValue })
  }
}
