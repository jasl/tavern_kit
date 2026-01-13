export function showNewIndicator(controller) {
  if (controller.hasNewIndicatorTarget) {
    controller.newIndicatorTarget.classList.remove("hidden")
  }
}

export function hideNewIndicator(controller) {
  if (controller.hasNewIndicatorTarget) {
    controller.newIndicatorTarget.classList.add("hidden")
  }
}

export function showLoadingIndicator(controller) {
  if (controller.hasLoadMoreIndicatorTarget) {
    controller.loadMoreIndicatorTarget.classList.remove("hidden")
  }
}

export function hideLoadingIndicator(controller) {
  if (controller.hasLoadMoreIndicatorTarget) {
    controller.loadMoreIndicatorTarget.classList.add("hidden")
  }
}

export function hideEmptyState(controller) {
  if (controller.hasEmptyStateTarget) {
    controller.emptyStateTarget.classList.add("hidden")
  }
}
