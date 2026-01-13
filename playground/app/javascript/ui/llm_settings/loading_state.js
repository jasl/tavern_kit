export function setTestLoading(controller, loading) {
  if (controller.hasTestButtonTarget) {
    controller.testButtonTarget.disabled = loading
  }

  if (controller.hasTestIconTarget) {
    controller.testIconTarget.className = loading
      ? "icon-[lucide--loader-2] size-4 animate-spin"
      : "icon-[lucide--wifi] size-4"
  }

  if (controller.hasTestTextTarget) {
    controller.testTextTarget.textContent = loading ? "Testing..." : "Test Connection"
  }
}

export function setFetchLoading(controller, loading) {
  if (controller.hasFetchModelsButtonTarget) {
    controller.fetchModelsButtonTarget.disabled = loading
  }

  if (controller.hasFetchModelsIconTarget) {
    controller.fetchModelsIconTarget.className = loading
      ? "icon-[lucide--loader-2] size-4 animate-spin"
      : "icon-[lucide--refresh-cw] size-4"
  }

  if (controller.hasFetchModelsTextTarget) {
    controller.fetchModelsTextTarget.textContent = loading ? "Fetching..." : "Fetch"
  }
}
