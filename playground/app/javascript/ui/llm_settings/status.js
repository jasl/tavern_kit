import { escapeHtml } from "../../dom_helpers"

export function displayConnectionResult(controller, result) {
  const statusContainer = document.getElementById(`connection-status-${controller.providerIdValue}`)
  if (!statusContainer) return

  if (result.success) {
    const response = result.response
      ? `"${escapeHtml(result.response.substring(0, 100))}${result.response.length > 100 ? "..." : ""}"`
      : ""

    statusContainer.innerHTML = `
        <div class="alert alert-success py-3">
          <span class="icon-[lucide--check-circle] size-5"></span>
          <div>
            <p class="font-medium">Connection successful!</p>
            ${response ? `<p class="text-sm opacity-80">${response}</p>` : ""}
          </div>
        </div>
      `
  } else {
    statusContainer.innerHTML = `
        <div class="alert alert-error py-3">
          <span class="icon-[lucide--alert-circle] size-5"></span>
          <div>
            <p class="font-medium">Connection failed</p>
            <p class="text-sm opacity-80">${escapeHtml(result.error)}</p>
          </div>
        </div>
      `
  }
}

export function displayFetchError(controller, message) {
  const statusContainer = document.getElementById(`connection-status-${controller.providerIdValue}`)
  if (statusContainer) {
    statusContainer.innerHTML = `
        <div class="alert alert-warning py-3">
          <span class="icon-[lucide--alert-triangle] size-5"></span>
          <div>
            <p class="font-medium">Could not fetch models</p>
            <p class="text-sm opacity-80">${escapeHtml(message)}</p>
          </div>
        </div>
      `
  }
}
